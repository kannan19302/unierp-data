-- PCC is the canonical provider-control permission namespace. Extend the
-- existing agent ceiling so a tenant or provider AI agent can never receive
-- provider control-center authority, even if application validation regresses.
CREATE OR REPLACE FUNCTION agent_permissions_within_control_plane_bound(perms TEXT[])
RETURNS BOOLEAN AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM unnest(perms) p
        WHERE p LIKE 'system.%'
           OR p LIKE 'platform.%'
           OR p LIKE 'pcc.%'
           OR p = '*'
    );
$$ LANGUAGE sql IMMUTABLE;
