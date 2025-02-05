---------------------------------
-- 1. Statistics formatting helpers for grafana
---------------------------------
create or replace function ecosystem.calculate_change(
    new_value bigint, old_value bigint
)
returns double precision
language plpgsql
as $$
begin
    if old_value = 0 then
        return null; -- avoid division by zero
    end if;
    return ((new_value - old_value) * 100.0) / old_value;
end;
$$;
