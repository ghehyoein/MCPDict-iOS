import unittest
from bundled_scope import include_table

class BundledScopeTests(unittest.TestCase):
    def test_administrative_levels_and_exceptions(self):
        self.assertTrue(include_table({'省':'甲'}))
        self.assertTrue(include_table({'省':'甲','市':'乙'}))
        self.assertFalse(include_table({'省':'甲','市':'乙','縣':'丙'}))
        self.assertFalse(include_table({'市':'乙','鎮':'丁'}))
        self.assertFalse(include_table({}))
        for category in ['歷史音','現代標準漢語','戲劇','域外方音']:
            self.assertTrue(include_table({'縣':'丙','音典分區':category+'－子類'}))
    def test_historical_marker_without_name_inference(self):
        self.assertFalse(include_table({'縣':'丙','歷史音':'#4D4D4D','音典分區':'兩浙－浙北'}))
        self.assertTrue(include_table({'省':'甲','市':'乙','歷史音':'#4D4D4D','音典分區':'兩浙－浙北'}))
        self.assertFalse(include_table({'縣':'丙','語言':'清末某地'}))
        for marker in ['0','#000000','#FFFFFF','#123456']:
            self.assertFalse(include_table({'縣':'丙','歷史音':marker}))
