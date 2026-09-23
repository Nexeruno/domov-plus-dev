create or replace function public.get_invitation_preview(p_token text)
returns table(household_name text, inviter_name text, target_email text, invitation_status text, expires_at timestamptz)
language plpgsql
security definer set search_path = ''
as $$
begin
  update public.household_invitations as invitation
  set status = 'expired', responded_at = now()
  where invitation.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and invitation.status = 'pending'
    and invitation.expires_at <= now();

  return query
  select household.name, inviter.display_name, invitation.target_email,
    invitation.status, invitation.expires_at
  from public.household_invitations as invitation
  join public.households as household on household.id = invitation.household_id
  join public.profiles as inviter on inviter.id = invitation.invited_by
  where invitation.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
end;
$$;

revoke all on function public.get_invitation_preview(text) from public;
grant execute on function public.get_invitation_preview(text) to anon, authenticated;
