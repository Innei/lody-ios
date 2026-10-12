import unittest
from project_geometry import viewport, visible_target, scroll_direction, scroll_points


def row(y, height=52):
    return {'frame': {'x': 16, 'y': y, 'width': 370, 'height': height}}


class ProjectGestureChecks(unittest.TestCase):
    def test_bottom_target_scrolls_toward_content_without_pulling_down_the_sheet(self):
        bounds = (134, 830)
        clean_worktree = row(810)
        self.assertFalse(visible_target(clean_worktree, bounds))
        direction = scroll_direction(clean_worktree, bounds, 'up')
        self.assertEqual(direction, 'down')
        start, end = scroll_points(direction, bounds)
        self.assertGreater(start, end, 'A lower preflight row requires an upward finger swipe')

    def test_partial_row_and_small_switch_need_a_complete_44_point_hit_region(self):
        bounds = (134, 830)
        self.assertFalse(visible_target(row(808), bounds))
        self.assertTrue(visible_target(row(770), bounds))
        self.assertFalse(visible_target(row(803, 28), bounds))
        self.assertTrue(visible_target(row(775, 28), bounds))

    def test_keyboard_and_native_header_bound_the_content_gesture(self):
        items = [
            {'type': 'Application', 'frame': {'x': 0, 'y': 0, 'width': 402, 'height': 874}},
            {'type': 'Button', 'AXLabel': 'Save', 'frame': {'y': 78, 'height': 44}},
            {'AXUniqueId': 'UIKeyboardLayoutStar', 'frame': {'y': 590}},
        ]
        bounds = viewport(items, {'Save'})
        self.assertEqual(bounds, (134, 578))
        self.assertFalse(visible_target(row(560), bounds))
        for direction in ['up', 'down']:
            self.assertTrue(all(bounds[0] < point < bounds[1] for point in scroll_points(direction, bounds)))


if __name__ == '__main__':
    unittest.main()
