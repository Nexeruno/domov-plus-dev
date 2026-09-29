-- Applied to DEV after public client deployment on 2026-09-29. Do not reapply.
-- Non-destructive: historical items, operation ledger and audit rows remain stored.

revoke all on table public.shopping_items from public, anon, authenticated;
revoke all on table public.shopping_sync_operations from public, anon, authenticated;

revoke all on function public.add_shopping_item(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.rename_shopping_item(uuid,text,bigint) from public, anon, authenticated;
revoke all on function public.mark_shopping_item_bought(uuid,bigint) from public, anon, authenticated;
revoke all on function public.restore_shopping_item(uuid,bigint) from public, anon, authenticated;
revoke all on function public.delete_shopping_item(uuid,bigint) from public, anon, authenticated;
revoke all on function public.undo_delete_shopping_item(uuid,bigint) from public, anon, authenticated;
revoke all on function public.list_current_shopping_items(uuid) from public, anon, authenticated;
revoke all on function public.get_shopping_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.apply_shopping_operation(uuid,uuid,uuid,text,jsonb,bigint,uuid,bigint) from public, anon, authenticated;
revoke all on function public.shopping_error_for_unique() from public, anon, authenticated;
revoke all on function public.track_shopping_revision() from public, anon, authenticated;

-- shopping_items belonged to this publication before this migration.
-- Preserve historical data in both shopping tables and the shared audit log.
alter publication supabase_realtime drop table public.shopping_items;
