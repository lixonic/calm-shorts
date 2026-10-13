from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_play_download import check


class PlayDownloadTests(unittest.TestCase):
    def test_uses_largest_variant_and_rejects_missing_or_over_budget_results(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'sizes.csv'
            path.write_text('MIN,MAX\n10,100\n20,480000001\n')
            with self.assertRaisesRegex(ValueError, 'safety budget'):
                check(path)
            path.write_text('MIN,MAX\n10,100\n20,200\n')
            self.assertEqual(check(path)['maximumCompressedDownloadBytes'], 200)
            path.write_text('')
            with self.assertRaises(ValueError):
                check(path)
