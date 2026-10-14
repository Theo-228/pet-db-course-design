CREATE TABLE petos.user_account (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    login_name text NOT NULL CHECK (length(btrim(login_name)) BETWEEN 3 AND 160),
    password_hash text NOT NULL CHECK (length(password_hash) BETWEEN 20 AND 500),
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISABLED')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX user_login_case_insensitive_unique
    ON petos.user_account (lower(login_name));

CREATE TABLE petos.workspace_membership (
    workspace_id bigint NOT NULL REFERENCES petos.workspace(id) ON DELETE RESTRICT,
    user_id bigint NOT NULL REFERENCES petos.user_account(id) ON DELETE RESTRICT,
    role text NOT NULL CHECK (role IN ('OWNER', 'EDITOR', 'VIEWER')),
    joined_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    PRIMARY KEY (workspace_id, user_id),
    CONSTRAINT membership_revoke_time CHECK (revoked_at IS NULL OR revoked_at >= joined_at)
);

CREATE INDEX membership_active_user_idx ON petos.workspace_membership (user_id, workspace_id)
    WHERE revoked_at IS NULL;

COMMENT ON TABLE petos.workspace_membership IS
    'Access to a workspace; roles are authorization boundaries, not different product modules';
