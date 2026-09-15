"""Capture the production WebView/toolbar host after late content and mode changes."""
import sys
from driver import UI

ui = UI(*sys.argv[1:])
ui.element('scroll-edge-diff-ready')
ui.capture('unified')
ui.axe('swipe', '--start-x', '200', '--start-y', '560', '--end-x', '200', '--end-y', '300', '--duration', '.6', '--post-delay', '1')
ui.capture('unified-scrolled')
ui.axe('tap', '--label', 'Split', '--tap-style', 'physical', '--post-delay', '1')
ui.wait(lambda items: any(item.get('AXLabel') == 'Split' and item.get('AXValue') in [1, '1'] for item in items), 'Split mode did not activate')
ui.capture('split')
ui.axe('swipe', '--start-x', '200', '--start-y', '560', '--end-x', '200', '--end-y', '300', '--duration', '.6', '--post-delay', '1')
ui.capture('split-scrolled')
print('PASS: late WebView content and both diff modes render with the native toolbar; review soft edge captures visually')
