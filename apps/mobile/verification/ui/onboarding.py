"""The signed-out welcome sheet cannot be dismissed and closes itself once an account arrives."""
import subprocess
import sys
from driver import UI, axe_session_dead
import catalog

ui = UI(sys.argv[1], sys.argv[2])


def tap(identifier, delay):
    """A press replaces this control. AXe can report a miss after the press already landed."""
    try:
        ui.axe('tap', '--id', identifier, '--post-delay', delay)
    except (subprocess.CalledProcessError, RuntimeError) as error:
        if axe_session_dead(error):
            raise


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

# Stop above the connect control. A drag that runs through it can press the button
# when the gesture is cut short by the next accessibility command.
start_y = sheet['y'] + 20
end_y = connect['frame']['y'] - 36
if end_y < start_y + 80:
    end_y = start_y + 80
x = sheet['x'] + sheet['width'] / 2
ui.axe('swipe', '--start-x', str(x), '--start-y', str(start_y),
       '--end-x', str(x), '--end-y', str(end_y), '--duration', '.5', '--post-delay', '1')
ui.element('onboarding-connect')
ui.capture('after-swipe')

tap('onboarding-connect', '.8')
assert ui.element('onboarding-code').get('AXValue') == 'WXYZ-1234' or 'WXYZ-1234' in (ui.element('onboarding-code').get('AXLabel') or '')
ui.wait(has_label(catalog.text('login.waiting')), 'Missing waiting copy')
ui.capture('waiting')

tap('auth-cancel', '.8')
ui.wait(has_label(catalog.text('auth.error.cancelledSignIn')), 'Missing cancelled error')
assert ui.element('onboarding-connect').get('AXLabel') == catalog.text('login.retry')
ui.capture('error')

tap('onboarding-connect', '1.2')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'onboarding-sheet' for item in items), 'Sheet did not close after sign-in')
ui.element('onboarding-preview')
ui.capture('closed')
print('Welcome sheet resists swipe, has no close button, walks connect → waiting → error → retry, and closes itself on sign-in.')
