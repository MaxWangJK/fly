"""Anonymous installation and daily-active records, without account linkage."""
from alembic import op
import sqlalchemy as sa

revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('analytics_devices',
        sa.Column('device_code', sa.String(32), primary_key=True),
        sa.Column('first_seen_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_analytics_devices_first_seen_at', 'analytics_devices', ['first_seen_at'])
    op.create_table('analytics_daily_active',
        sa.Column('id', sa.BigInteger().with_variant(sa.Integer(), 'sqlite'), primary_key=True, autoincrement=True),
        sa.Column('device_code', sa.String(32), sa.ForeignKey('analytics_devices.device_code'), nullable=False),
        sa.Column('active_date', sa.Date(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint('device_code', 'active_date', name='uq_analytics_daily_device_date'))
    op.create_index('ix_analytics_daily_active_device_code', 'analytics_daily_active', ['device_code'])
    op.create_index('ix_analytics_daily_active_active_date', 'analytics_daily_active', ['active_date'])


def downgrade():
    op.drop_table('analytics_daily_active')
    op.drop_table('analytics_devices')
