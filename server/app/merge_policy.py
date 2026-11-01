"""Deterministic automatic field merge, also implemented by the LAN authority."""
import json


def merge_fields(before, payload, fields, concurrent_fields, clocks, incoming, mutation_id, now_ms):
    def clock(raw, fallback):
        if (isinstance(raw, list) and len(raw) == 2 and type(raw[0]) is int
                and raw[0] >= 0 and isinstance(raw[1], str) and len(raw[1]) <= 80):
            return [now_ms if raw[0] > now_ms + 300000 else raw[0], raw[1]]
        return [fallback, mutation_id]

    data = dict(before)
    for field in fields:
        prior = clock(clocks.get(field), 0)
        stamp = clock(incoming.get(field), now_ms)
        concurrent = field in concurrent_fields
        if field == 'answers_json' and isinstance(payload[field], str):
            try:
                answers = json.loads(before.get(field, '{}'))
                values = json.loads(payload[field])
                if isinstance(answers, dict) and isinstance(values, dict):
                    for key in set(answers) | set(values):
                        child = f'answers_json/{key}'
                        if key not in values and child not in incoming:
                            continue
                        old = clock(clocks.get(child, clocks.get(field)), 0)
                        new = clock(incoming.get(child, incoming.get(field)), now_ms)
                        if concurrent and tuple(new) < tuple(old):
                            continue
                        changed = answers.get(key) != values.get(key)
                        if key in values:
                            answers[key] = values[key]
                        else:
                            answers.pop(key, None)
                        if not concurrent and changed and old[0] >= new[0]:
                            new[0] = old[0] + 1
                        clocks[child] = new
                    data[field] = json.dumps(answers, ensure_ascii=False, separators=(',', ':'))
                    clocks[field] = max(stamp, prior)
                    continue
            except (ValueError, TypeError):
                pass
        if field in before and concurrent and tuple(stamp) < tuple(prior):
            continue
        data[field] = payload[field]
        if not concurrent and before.get(field) != payload[field] and prior[0] >= stamp[0]:
            stamp[0] = prior[0] + 1
        clocks[field] = stamp
    return data


def disambiguate_unique_fields(entity, record_id, data, existing):
    fields = {'orders': ['order_number'], 'tags': ['scope', 'name'],
              'file_tags': ['normalized_name']}.get(entity, [])
    if not fields or any(f not in data for f in fields):
        return
    rows = [r for r in existing if r.get('id') != data.get('id')]
    def collides(): return any(all(r.get(f) == data[f] for f in fields) for r in rows)
    if not collides():
        return
    field, original = fields[-1], str(data[fields[-1]])
    suffix, attempt = record_id.replace('-', '')[:12], 0
    while True:
        mark = f' ({suffix}{"" if attempt == 0 else "-" + str(attempt)})'
        limit = (120 if entity == 'orders' else 100 if entity == 'file_tags' else 80) - len(mark)
        prefix = original.encode('utf-16-le')[:limit * 2].decode('utf-16-le', errors='ignore')
        data[field] = prefix + mark
        attempt += 1
        if not collides():
            break
    if entity == 'file_tags':
        data['name'] = data[field]
