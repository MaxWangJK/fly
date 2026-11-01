"""Automatic field clocks and one-use device enrollment, preserving existing users."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade():
    json_type = sa.JSON().with_variant(postgresql.JSONB(), 'postgresql')
    for table in ('sync_records', 'sync_changes'):
        op.add_column(table, sa.Column('field_clocks', json_type, nullable=False, server_default='{}'))
    op.create_table('device_enrollment_codes',
        sa.Column('code_hash', sa.String(64), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('used_at', sa.DateTime(timezone=True)))
    # Existing candidates remain as an audit; the previously accepted record is
    # already canonical. Upgrading never reapplies old candidate payloads.
    op.execute('UPDATE sync_conflicts SET resolved_at=CURRENT_TIMESTAMP WHERE resolved_at IS NULL')


def downgrade():
    op.drop_table('device_enrollment_codes')
    for table in ('sync_changes', 'sync_records'):
        op.drop_column(table, 'field_clocks')
