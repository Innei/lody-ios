"""Production team pages with offline permissions, invitation, join and ownership outcomes."""
import subprocess
import sys
import time
import catalog
from driver import UI
from project_geometry import viewport, visible_target

ui = UI(*sys.argv[1:])


def tap(identifier):
    ui.axe('tap', '--id', identifier)


def button(label):
    node = ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == label and item.get('type') == 'Button' and item.get('enabled', True)), None), f'Missing button {label}')
    frame = node['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2))


def text(value):
    return ui.wait(lambda items: next((item for item in items if value in str(item.get('AXLabel', ''))), None), f'Missing {value}')


def reveal(identifier):
    for _ in range(12):
        node = next((item for item in ui.state() if item.get('AXUniqueId') == identifier), None)
        if node and 80 < node['frame']['y'] < 760:
            return node
        ui.axe('swipe', '--start-x', '190', '--start-y', '720', '--end-x', '190', '--end-y', '350', '--duration', '.3')
    raise AssertionError(f'Could not reveal {identifier}')


def scene(case):
    started = time.monotonic()
    ui.open_case('team-preview')
    ui.element('team-fixture:owner')
    reveal('team-fixture:' + case)
    tap('team-fixture:' + case)
    if case in ['join', 'wrong-recipient', 'unverified']:
        text(catalog.text('team.joinWorkspace') if case == 'join' else catalog.text('team.openOfficial'))
        ui.wait(lambda items: any(item.get('type') == 'Button' and item.get('AXLabel') == catalog.text('team.refresh') and item.get('frame', {}).get('y', 999) < 170 for item in items), 'Pushed join page lost its native Refresh header')
    else:
        ui.element('member:self')
        if case != 'member':
            ui.wait(lambda items: any(item.get('type') == 'Button' and item.get('AXLabel') == catalog.text('team.invite') and item.get('frame', {}).get('y', 999) < 170 for item in items), 'Pushed team page lost its native Invite header')
    print(f'ENTRY {case}: {time.monotonic() - started:.2f}s')


def confirm(label):
    sheet = ui.wait(lambda items: next((item for item in items if item.get('role') == 'AXSheet' and item.get('AXLabel') == label), None), f'Missing confirmation {label}')

    def walk(node):
        yield node
        for child in node.get('children', []):
            yield from walk(child)

    action = next(item for item in walk(sheet) if item.get('type') == 'Button' and item.get('AXLabel') == label)
    frame = action['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2))


def pasteboard():
    return subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True).strip()


scene('owner')
assert ui.element('member:casey')['frame']['height'] >= 44
tap('member:casey')
button(catalog.text('team.admin'))
ui.wait(lambda items: any(item.get('AXUniqueId') == 'member:casey' and item.get('AXValue') == catalog.text('team.admin') for item in items), 'Role change did not refresh')
ui.capture('owner-role-updated')
button(catalog.text('team.invite'))
tap('team-email')
ui.type_into('team-email', 'new@example.invalid')
tap('team-invite-role')
button(catalog.text('team.admin'))
ui.capture('invitation-filled')
button(catalog.text('team.invite'))
reveal('invitation:invited-1')
tap('invitation:invited-1')
button(catalog.text('team.copyLink'))
ui.wait(lambda _: pasteboard() == 'https://lody.ai/invite/invited-1', 'Invitation URL was not copied')
ui.capture('invitation-created-and-copied')
tap('invitation:invited-1')
button(catalog.text('team.revoke'))
button(catalog.text('common.cancel'))
ui.element('invitation:invited-1')
tap('invitation:invited-1')
button(catalog.text('team.revoke'))
confirm(catalog.text('team.revoke'))
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'invitation:invited-1' for item in items), 'Revoked invitation remained')
reveal('team-create-link')
tap('team-create-link')
reveal('team-copy-join')
tap('team-copy-join')
ui.wait(lambda _: pasteboard() == 'https://lody.ai/join/fixture-join-1', 'Join URL was not copied')
ui.capture('join-link-created')
tap('team-create-link')
confirm(catalog.text('team.regenerateLink'))
reveal('team-copy-join')
tap('team-copy-join')
ui.wait(lambda _: pasteboard() == 'https://lody.ai/join/fixture-join-2', 'Join URL did not rotate')
reveal('request:pat-request')
tap('request:pat-request')
text('Please add me to review the release.')
button(catalog.text('team.approve'))
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'request:pat-request' for item in items), 'Reviewed join request remained')
ui.capture('join-request-approved')
reveal('team-transfer')
tap('team-transfer')
ui.element('member:casey')
tap('member:casey')
tap('team-transfer-confirmation')
ui.type_into('team-transfer-confirmation', 'Studio')
ui.capture('ownership-confirmation')
button(catalog.text('common.cancel'))
ui.element('member:casey')
tap('member:casey')
tap('team-transfer-confirmation')
ui.type_into('team-transfer-confirmation', 'Studio')
button(catalog.text('team.transfer'))
ui.wait(lambda items: any(item.get('AXUniqueId') == 'member:self' and (item.get('AXValue') == catalog.text('team.admin') or catalog.text('team.admin') in str(item.get('AXLabel', ''))) for item in items), 'Transferred ownership did not refresh role')
ui.capture('ownership-transferred')

scene('member')
assert not any(item.get('AXLabel') == catalog.text('team.invite') and item.get('type') == 'Button' for item in ui.state())
reveal('team-leave')
tap('team-leave')
button(catalog.text('common.cancel'))
ui.element('team-leave')
ui.capture('member-leave-cancelled')
tap('team-leave')
confirm(catalog.text('team.leave'))
ui.element('team-fixture:member')

scene('admin')
button(catalog.text('team.invite'))
ui.element('team-email')
ui.capture('admin-invitation')
button(catalog.text('common.cancel'))
assert not any(item.get('AXUniqueId') == 'team-transfer' for item in ui.state())

scene('remove-failure')
frame = ui.element('member:casey')['frame']
y = frame['y'] + frame['height'] / 2
ui.axe('swipe', '--start-x', str(frame['x'] + frame['width'] - 20), '--start-y', str(y), '--end-x', str(frame['x'] + frame['width'] / 2), '--end-y', str(y), '--duration', '.4')
button(catalog.text('team.remove'))
confirm(catalog.text('team.remove'))
text(catalog.text('team.requestFailed'))
ui.element('member:casey')
ui.capture('rejected-removal-retained-member')

scene('limit')
text(catalog.text('team.limitReached'))
assert any(item.get('AXLabel') == catalog.text('team.invite') and not item.get('enabled', True) for item in ui.state())
ui.capture('member-limit')

scene('paid')
button(catalog.text('team.invite'))
text('$10.00')
text('$20.00')
ui.capture('server-seat-preview')
button(catalog.text('common.cancel'))

scene('invite-failure')
button(catalog.text('team.invite'))
tap('team-email')
ui.type_into('team-email', 'retained@example.invalid')
button(catalog.text('team.invite'))
ui.element('team-form-error')
assert ui.element('team-email').get('AXValue') == 'retained@example.invalid'
ui.capture('invitation-failure-retains-draft')
button(catalog.text('common.cancel'))

scene('role-loss')
tap('member:casey')
button(catalog.text('team.admin'))
text(catalog.text('team.permissionDenied'))
assert not any(item.get('AXLabel') == catalog.text('team.invite') and item.get('type') == 'Button' for item in ui.state())
ui.capture('role-loss-refreshed')

scene('paged')
search = ui.element('list-search')
assert search.get('type') in ['SearchField', 'TextField'] and search.get('enabled', True), 'Member search field unavailable'
assert catalog.text('team.search') in [search.get('AXLabel'), search.get('AXValue')], 'Member search belongs to another page'
frame = search['frame']
assert frame['width'] > 0 and frame['height'] > 0, 'Member search has no hit area'
ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2))
ui.axe('type', 'Sam Pagination')
ui.element('member:sam')
ui.capture('search-next-page')

scene('join')
tap('team-received-invitations')
tap('received:received')
tap('team-accept')
text(catalog.text('team.invitationAccepted'))
ui.capture('invitation-accepted')

scene('join')
tap('team-join-link')
ui.type_into('team-join-link', 'https://lody.ai/join/fixture-join')
tap('team-open-link')
tap('team-join-reason')
focused_items = ui.wait(lambda items: items if any(str(item.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar') for item in items) else None, 'Reason keyboard did not appear')
focused_reason = next(item for item in focused_items if item.get('AXUniqueId') == 'team-join-reason')
ui.capture('join-request-focused')
assert focused_reason.get('type') == 'TextArea' and focused_reason.get('enabled', True), 'Focused Reason is not an enabled text area'
assert visible_target(focused_reason, viewport(focused_items, {catalog.text('team.refresh')})), 'Focused Reason must remain fully visible above the keyboard and below navigation controls'
ui.type_into('team-join-reason', 'Please add me.')
ui.capture('join-request-filled')
tap('team-submit-request')
text(catalog.text('team.requestPending'))
ui.capture('join-request-pending')

scene('wrong-recipient')
text(catalog.text('team.recipientMismatch'))
assert not any(item.get('AXUniqueId') == 'team-accept' for item in ui.state())
ui.capture('invitation-account-mismatch')

scene('unverified')
text(catalog.text('team.verifyEmail'))
assert not any(item.get('AXUniqueId') == 'team-submit-request' for item in ui.state())
ui.capture('email-verification-required')
print('PASS: owner/admin/member rights, invite/copy/revoke, join link rotation, request approval, transfer confirmation, leave, limits, seat preview, rejected draft, permission refresh and paged search.')
