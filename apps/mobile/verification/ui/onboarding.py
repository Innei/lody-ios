"""The signed-out welcome sheet cannot be dismissed and closes itself once an account arrives."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])


def has_label(text):
    return lambda items: any(item.get('AXLabel') == text for item in items)


connect = ui.element('onboarding-connect')
screen = ui.state()[0]['frame']
sheet = ui.element('onboarding-sheet')['frame']
if screen['width'] >= 700:
    assert sheet['width'] < screen['width'] - 80, ('iPad welcome must have side margins', sheet, screen)
    assert sheet['height'] < screen['height'] - 80, ('iPad welcome must have top and bottom margins', sheet, screen)
    assert abs(sheet['x'] + sheet['width'] / 2 - screen['x'] - screen['width'] / 2) < 4, ('Welcome is not horizontally centered', sheet, screen)
    # UIKit's form sheet uses the available area around system safe areas.
    assert abs(sheet['y'] + sheet['height'] / 2 - screen['y'] - screen['height'] / 2) < 16, ('Welcome is not vertically centered', sheet, screen)
assert connect['frame']['height'] >= 44
assert not any(item.get('AXUniqueId') == 'xmark' or item.get('AXLabel') == catalog.system('close') for item in ui.state()), 'Welcome sheet must not offer a close button'
for key in ('onboarding.sessions.title', 'onboarding.reply.title', 'onboarding.privacy.title'):
    ui.wait(lambda items, key=key: any(catalog.text(key) in (item.get('AXLabel') or '') for item in items), f'Missing feature {key}')
ui.capture('idle')

ui.axe('swipe', '--start-x', str(sheet['x'] + sheet['width'] / 2), '--start-y', str(sheet['y'] + 20),
       '--end-x', str(sheet['x'] + sheet['width'] / 2), '--end-y', str(sheet['y'] + sheet['height'] - 20), '--duration', '.5', '--post-delay', '1')
ui.element('onboarding-connect')
ui.capture('after-swipe')

ui.axe('tap', '--id', 'onboarding-connect', '--post-delay', '.8')
assert ui.element('onboarding-code').get('AXValue') == 'WXYZ-1234' or 'WXYZ-1234' in (ui.element('onboarding-code').get('AXLabel') or '')
ui.wait(has_label(catalog.text('login.waiting')), 'Missing waiting copy')
ui.capture('waiting')

ui.axe('tap', '--id', 'auth-cancel', '--post-delay', '.8')
ui.wait(has_label(catalog.text('auth.error.cancelledSignIn')), 'Missing cancelled error')
assert ui.element('onboarding-connect').get('AXLabel') == catalog.text('login.retry')
ui.capture('error')

ui.axe('tap', '--id', 'onboarding-connect', '--post-delay', '1.2')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'onboarding-sheet' for item in items), 'Sheet did not close after sign-in')
ui.element('onboarding-preview')
ui.capture('closed')
print('Welcome sheet resists swipe, has no close button, walks connect → waiting → error → retry, and closes itself on sign-in.')
