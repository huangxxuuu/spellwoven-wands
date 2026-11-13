"""Negative regressions: bilingual agreement must not conceal stale site data."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_site_catalog import check_atlas, check_cards, check_materials


class CatalogRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((ROOT / "site/dist/catalog.json").read_text(encoding="utf8"))
        cls.tiles = check_atlas(ROOT / "site/dist")

    def test_current_export(self):
        check_cards(self.data, "zh", self.tiles)
        check_materials(self.data, "zh", ROOT / "site/dist")

    def material_rejects(self, mutate, failure):
        changed = copy.deepcopy(self.data)
        ingredients = [i for c in changed["cards"] for r in c["recipes"] for i in r["ingredients"]]
        mutate(ingredients)
        with self.assertRaisesRegex(AssertionError, failure):
            check_materials(changed, "zh", ROOT / "site/dist")

    def test_swapped_material_icons(self):
        def swap(ingredients):
            left = ingredients[0]
            right = next(i for i in ingredients if i["prefab"] != left["prefab"])
            left["icon"], right["icon"] = right["icon"], left["icon"]
        self.material_rejects(swap, "material icon identity")

    def test_wiki_link_for_wrong_material(self):
        def swap(ingredients):
            left = next(i for i in ingredients if i["wiki"])
            right = next(i for i in ingredients if i["wiki"] and i["href"] != left["href"])
            left["href"] = right["href"]
        self.material_rejects(swap, "material wiki identity")

    def test_mod_material_external_link(self):
        def replace(ingredients):
            material = next(i for i in ingredients if i["prefab"] == "nw_blank")
            material.update(wiki=True, href="https://dontstarve.huijiwiki.com/wiki/nw_blank")
        self.material_rejects(replace, "Mod material must use local guide")

    def rejects(self, mutate, failure):
        changed = copy.deepcopy(self.data)
        card = next(c for c in changed["cards"] if c["id"] == "spark")
        mutate(card)
        with self.assertRaisesRegex(AssertionError, failure):
            check_cards(changed, "zh", self.tiles)

    def test_stale_numeric_value_in_one_mode(self):
        self.rejects(lambda c: c["modeValues"]["balanced"].update(mana=999), "balanced.*mana")

    def test_stale_default_value(self):
        self.rejects(lambda c: c.update(mana=999), "default value")

    def test_recipe_material_identity(self):
        self.rejects(lambda c: c["recipes"][0]["ingredients"][0].update(prefab="redgem"), "recipe or mode eligibility differs")

    def test_recipe_material_quantity(self):
        self.rejects(lambda c: c["recipes"][0]["ingredients"][0].update(count=999), "recipe or mode eligibility differs")

    def test_recipe_mode_eligibility(self):
        self.rejects(lambda c: c["recipes"][0]["availableModes"].append("balanced_loot"), "recipe or mode eligibility differs")

    def test_station_filter(self):
        self.rejects(lambda c: c.update(station="武器刻印台"), "station filter")

    def test_wrong_icon_index(self):
        self.rejects(lambda c: c.update(iconIndex=c["iconIndex"] + 1), "icon index")

    def test_wrong_drop_mode_probability(self):
        changed = copy.deepcopy(self.data)
        changed["fallbackDropChance"]["balanced_loot"] = 0.25
        with self.assertRaisesRegex(AssertionError, "fallback drop chance"):
            check_cards(changed, "zh", self.tiles)

    def test_displayed_recipe_quantity_without_metadata_change(self):
        self.rejects(lambda c: c["sources"].__setitem__(0, c["sources"][0].replace("×1", "×999", 1)),
                     "displayed recipe ingredients")

    def test_displayed_probability_without_metadata_change(self):
        self.rejects(lambda c: c.update(sources=[source.replace("0.05%", "25%") for source in c["sources"]]),
                     "displayed fallback probability")


if __name__ == "__main__":
    unittest.main()
