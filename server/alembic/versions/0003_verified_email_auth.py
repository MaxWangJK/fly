"""Verified email registration, single-use challenges and persistent limits."""
from alembic import op
import sqlalchemy as sa

revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('users', sa.Column('email_verified_at', sa.DateTime(timezone=True), nullable=True))
    op.create_table('email_auth_challenges',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('email', sa.String(320), nullable=False),
        sa.Column('purpose', sa.String(20), nullable=False),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('captcha_hash', sa.String(64), nullable=False),
        sa.Column('captcha_expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('captcha_attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('captcha_used_at', sa.DateTime(timezone=True)),
        sa.Column('code_hash', sa.String(64)),
        sa.Column('code_expires_at', sa.DateTime(timezone=True)),
        sa.Column('code_attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('sent_at', sa.DateTime(timezone=True)),
        sa.Column('ticket_hash', sa.String(64), unique=True),
        sa.Column('ticket_expires_at', sa.DateTime(timezone=True)),
        sa.Column('verified_at', sa.DateTime(timezone=True)),
        sa.Column('consumed_at', sa.DateTime(timezone=True)))
    op.create_index('ix_email_auth_challenges_email', 'email_auth_challenges', ['email'])
    op.create_table('auth_rate_buckets',
        sa.Column('key', sa.String(64), primary_key=True),
        sa.Column('window_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('count', sa.Integer(), nullable=False, server_default='0'))


def downgrade():
    op.drop_table('auth_rate_buckets')
    op.drop_index('ix_email_auth_challenges_email', table_name='email_auth_challenges')
    op.drop_table('email_auth_challenges')
    op.drop_column('users', 'email_verified_at')
