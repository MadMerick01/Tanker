"""Validate the distributed layout, not just the development checkout."""
import json
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

from tools.package import build


class PackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = build(Path(self.temp.name) / 'tanker.zip')

    def test_archive_layout_is_standalone(self):
        with ZipFile(self.output) as archive:
            names = set(archive.namelist())
            for name in ('scripts/tanker/modScript.lua', 'lua/ge/extensions/tanker/core.lua',
                         'lua/ge/extensions/tanker/wrist.lua', 'ui/modules/apps/Tanker/app.json',
                         'ui/modules/apps/Tanker/app.js', 'ui/modules/apps/Tanker/app.html',
                         'ui/modules/apps/Tanker/app.png', 'ui/modules/apps/Tanker/sounds/drone.ogg',
                        'ui/modules/apps/Tanker/sounds/blast.ogg', 'lua/ge/extensions/tanker/drone.lua', 'README.md', 'CHANGELOG.md', 'docs/DESIGN.md', 'config.example.json'):
                self.assertIn(name, names)
            self.assertFalse(any(n.startswith(('settings/', 'tests/', 'tools/', 'tanker/')) for n in names))
            self.assertFalse(any(n.endswith(('.pyc', 'save-a.json', 'save-b.json')) for n in names))
            self.assertIsNone(archive.testzip())

    def test_manifest_and_wiring_agree(self):
        prefix = 'ui/modules/apps/Tanker/'
        with ZipFile(self.output) as archive:
            manifest = json.loads(archive.read(prefix + 'app.json'))
            config = json.loads(archive.read('config.example.json'))
            self.assertEqual(manifest['appName'], 'Tanker')
            self.assertEqual(manifest['directive'], 'tankerHud')
            self.assertIn('tanker-hud', manifest['domElement'])
            self.assertIn(b"'tankerHud'", archive.read(prefix + 'app.js'))
            self.assertIn(b'/ui/modules/apps/Tanker/app.html', archive.read(prefix + 'app.js'))
            self.assertIn(b'tanker_core', archive.read('scripts/tanker/modScript.lua'))
            self.assertIn('start', config)
            self.assertTrue(archive.read(prefix + 'app.png').startswith(b'\x89PNG'))

    def test_starter_truck_is_packaged(self):
        prefix = 'vehicles/pickup/'
        with ZipFile(self.output) as archive:
            config = json.loads(archive.read(prefix + 'tankerstarter.pc'))
            info = json.loads(archive.read(prefix + 'info_tankerstarter.json'))
            thumbnail = archive.read(prefix + 'tankerstarter.jpg')
            module = archive.read('lua/ge/extensions/tanker/vehicle.lua')
        self.assertEqual(config['model'], 'pickup')
        self.assertEqual(config['parts']['pickup_bedextra_long'], 'pickup_bed_cargo_load_box_XL')
        self.assertEqual(config['parts']['cargo_load_box_XL_A_90deg'], 'cargo_load_tank_XL_A_90deg')
        self.assertEqual(info['Configuration'], config['Configuration'])
        self.assertTrue(thumbnail.startswith(b'\xff\xd8'))
        self.assertIn(b"'vehicles/pickup/tankerstarter.pc'", module)

    def test_hoon_car_is_packaged(self):
        prefix = 'vehicles/barstow/'
        with ZipFile(self.output) as archive:
            config = json.loads(archive.read(prefix + 'hoonold1.pc'))
            info = json.loads(archive.read(prefix + 'info_hoonold1.json'))
            thumbnail = archive.read(prefix + 'hoonold1.jpg')
            module = archive.read('lua/ge/extensions/tanker/hoonCar.lua')
            fast = json.loads(archive.read(prefix + 'hoonfast2.pc'))
            fastInfo = json.loads(archive.read(prefix + 'info_hoonfast2.json'))
            fastThumb = archive.read(prefix + 'hoonfast2.jpg')
        self.assertEqual(config['model'], 'barstow')
        self.assertEqual(config['parts']['barstow_rollcage'], 'barstow_rollcage')
        self.assertEqual(info['Configuration'], config['Configuration'])
        self.assertTrue(thumbnail.startswith(b'\xff\xd8'))
        self.assertEqual(fast['model'], 'barstow')
        self.assertEqual(fast['parts']['barstow_engine'], 'barstow_engine_v8_353')
        self.assertEqual(fastInfo['Configuration'], fast['Configuration'])
        self.assertTrue(fastThumb.startswith(b'\xff\xd8'))
        self.assertIn(b"'vehicles/barstow/'", module)
        self.assertIn(b"'hoonold1', 'hoonfast2'", module)

    def test_build_is_deterministic(self):
        again = build(Path(self.temp.name) / 'again.zip')
        self.assertEqual(self.output.read_bytes(), again.read_bytes())


if __name__ == '__main__':
    unittest.main()
