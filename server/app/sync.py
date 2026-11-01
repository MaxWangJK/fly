import hashlib
import json
from uuid import UUID, uuid5
from fastapi import HTTPException
from sqlalchemy import select
from .models import ProcessedMutation, SyncChange, SyncConflict, SyncRecord, now, uid
from .merge_policy import merge_fields, disambiguate_unique_fields


def record_json(record):
    return {'entityType': record.entity_type, 'recordId': record.record_id,
            'version': record.version, 'data': record.data,
            'deletedAt': record.deleted_at.isoformat() if record.deleted_at else None,
            'fieldClocks': record.field_clocks or {}}


def conflict_copy(db, device, entity, candidate):
    if entity not in ('attachments', 'note_blocks') or 'id' not in candidate:
        return None
    data = dict(candidate)
    data['id'] = uid()
    if entity == 'attachments':
        original = data.get('original_name', 'file')
        stem, dot, extension = original.rpartition('.')
        suffix = f' (conflict {device.device_name} {now():%Y-%m-%d})'
        data['original_name'] = (stem + suffix + dot + extension) if dot else original + suffix
        data['display_name'] = data['original_name']
        data['file_name'] = data['original_name']
    else:
        data['sort_order'] = data.get('sort_order', 0) + 1
    record_id = str(uuid5(UUID('e8cd67db-7ae2-4ea8-bba7-baeeb52375a1'),
                         entity + ':' + json.dumps([data['id']], separators=(',', ':'))))
    record = SyncRecord(user_id=device.user_id, entity_type=entity, record_id=record_id,
                        version=1, data=data, last_device_id=device.id)
    db.add(record)
    db.add(SyncChange(user_id=device.user_id, entity_type=entity, record_id=record_id,
                      version=1, data=data, operation='upsert', changed_fields=list(data), device_id=device.id))
    return record_id


def accept(db, device, mutation):
    user_id = device.user_id
    mutation_id = str(mutation.mutation_id)
    request_hash = hashlib.sha256(json.dumps(mutation.model_dump(mode='json', by_alias=True),
                                            sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    previous = db.get(ProcessedMutation, (user_id, mutation_id))
    if previous:
        if previous.request_hash != request_hash:
            raise HTTPException(409, 'Mutation ID reused with different content')
        return previous.result
    key = (user_id, mutation.entity_type, str(mutation.record_id))
    record = db.get(SyncRecord, key)
    current = record.version if record else 0
    if mutation.base_version > current:
        raise HTTPException(409, 'baseVersion ahead of server')
    if record is None and mutation.base_version != 0:
        raise HTTPException(409, 'Missing base record')
    changed = set()
    if record and mutation.base_version < current:
        history = db.scalars(select(SyncChange).where(
            SyncChange.user_id == user_id, SyncChange.entity_type == mutation.entity_type,
            SyncChange.record_id == str(mutation.record_id), SyncChange.version > mutation.base_version)).all()
        for change in history:
            changed.update(change.changed_fields)
            if change.operation in ('delete', 'restore'):
                changed.add('__lifecycle__')
    overlap = {field for field in set(mutation.changed_fields) & changed
               if field not in {'updated_at', 'created_at', 'version'}
               and record.data.get(field) != mutation.payload.get(field)}
    delete_conflict = bool(record and ((record.deleted_at and mutation.operation == 'upsert') or
                                       (mutation.operation == 'delete' and changed) or
                                       ('__lifecycle__' in changed)))
    binary_conflict = (mutation.entity_type == 'attachments' and bool(overlap & {'sha256'})
                       and record.data.get('deletion_batch') != 'permanent')
    conflict = None
    if overlap or delete_conflict:
        conflict = SyncConflict(id=uid(), user_id=user_id, entity_type=mutation.entity_type,
            record_id=str(mutation.record_id), fields=sorted(overlap) or ['__lifecycle__'],
            local_candidate=mutation.payload, server_candidate=dict(record.data),
            kind='delete_update' if delete_conflict else 'binary' if binary_conflict else 'same_field',
            device_id=device.id, resolved_at=now())
        db.add(conflict)
        if binary_conflict:
            conflict_copy(db, device, mutation.entity_type, {**record.data, **mutation.payload})
        elif mutation.entity_type == 'note_blocks' and overlap:
            conflict_copy(db, device, mutation.entity_type, record.data)
    if record is None:
        record = SyncRecord(user_id=user_id, entity_type=mutation.entity_type,
            record_id=str(mutation.record_id), version=0, data={}, last_device_id=device.id)
        db.add(record)
    # An explicit restore must be based on the current tombstone; stale restore cannot resurrect.
    blocked = bool((mutation.entity_type == 'attachments' and record.data.get('deletion_batch') == 'permanent') or
                   record.deleted_at and mutation.operation != 'delete' and
                   not (mutation.operation == 'restore' and mutation.base_version == current))
    if not blocked and not binary_conflict:
        clocks = dict(record.field_clocks or {})
        data = merge_fields(record.data, mutation.payload, mutation.changed_fields, changed,
            clocks, {k: list(v) for k, v in mutation.field_clocks.items()}, mutation_id, int(now().timestamp() * 1000))
        if mutation.entity_type in ('orders', 'tags', 'file_tags'):
            others = db.scalars(select(SyncRecord).where(SyncRecord.user_id == user_id,
                                SyncRecord.entity_type == mutation.entity_type)).all()
            disambiguate_unique_fields(mutation.entity_type, str(mutation.record_id), data,
                                       (r.data for r in others))
        if mutation.operation == 'delete' and record.version == 0:
            data.update(mutation.payload)  # Preserve keys for a record deleted before its first upload.
        if 'deleted_at' in data:
            data['deleted_at'] = int(now().timestamp()) if mutation.operation == 'delete' else None
        record.data = data
        record.field_clocks = clocks
        record.deleted_at = now() if mutation.operation == 'delete' else None
        record.version += 1
        record.last_device_id = device.id
        record.server_updated_at = now()
        change = SyncChange(user_id=user_id, entity_type=record.entity_type,
            record_id=record.record_id, version=record.version, operation=mutation.operation,
            changed_fields=mutation.changed_fields, data=dict(record.data),
            deleted_at=record.deleted_at, device_id=device.id, field_clocks=clocks)
        db.add(change)
        db.flush()
    result = {'mutationId': mutation_id, 'status': 'accepted', 'autoMerged': conflict is not None,
              'record': record_json(record), 'conflictId': conflict.id if conflict else None}
    db.add(ProcessedMutation(user_id=user_id, mutation_id=mutation_id,
                            request_hash=request_hash, result=result))
    db.flush()
    return result
