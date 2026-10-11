"""Fly account and sync foundation.

Revision is frozen: the table definitions below are loaded from a versioned schema.
"""
from alembic import op
from app.schema_v1 import metadata

revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    metadata.create_all(op.get_bind())


def downgrade():
    metadata.drop_all(op.get_bind())
