"use strict";
const english = document.documentElement.lang === "en";
const t = (zh, en) => english ? en : zh;

const form = document.querySelector("#filters");
const query = document.querySelector("#q");
const category = document.querySelector("#category");
const tagFilters = document.querySelector("#tags");
const station = document.querySelector("#station");
const fuzzy = document.querySelector("#fuzzy");
const descriptions = document.querySelector("#descriptions");
const entries = document.querySelector("#entries");
const count = document.querySelector("#count");
const dialog = document.querySelector("#card-detail");
const noRecipe = t("无制作配方", "No crafting recipe");

function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (className) node.className = className;
    return node;
}

function icon(card) {
    const tile = element("span", "", "tile");
    tile.setAttribute("aria-hidden", "true");
    const pos = card.iconIndex;
    tile.style.backgroundPosition = (pos % 16) / 15 * 100 + "% " + Math.floor(pos / 16) / 15 * 100 + "%";
    return tile;
}

function signed(value) {
    return value > 0 ? "+" + value : String(value);
}

function showCard(card) {
    const heading = element("h2", card.name);
    heading.id = "detail-name";
    const title = element("div", "", "detail-title");
    title.append(icon(card), heading);
    const attributes = element("dl", undefined, "spell-attrs");
    for (const [label, value] of card.fields) {
        attributes.append(element("dt", label), element("dd", value));
    }
    const sources = element("ul");
    card.sources.forEach(source => sources.append(element("li", source)));
    const details = element("div", undefined, "spell-data");
    details.hidden = true;
    details.append(element("p", card.detailedEffect, "effect"));
    const toggle = element("button", t("详细数据", "Detailed data"), "detail-toggle");
    toggle.type = "button";
    toggle.setAttribute("aria-expanded", "false");
    toggle.addEventListener("click", () => {
        details.hidden = !details.hidden;
        toggle.setAttribute("aria-expanded", String(!details.hidden));
        toggle.textContent = details.hidden ? t("详细数据", "Detailed data") : t("收起数据", "Hide data");
    });
    document.querySelector("#detail-content").replaceChildren(title,
        element("small", [card.category, card.subgroup, card.rarity, ...card.tags].filter(Boolean).join("　/　")),
        element("p", card.tags.join(" · "), "card-tags"),
        element("p", card.effect, "effect"), element("h3", t("法术属性", "Spell stats")), attributes, toggle, details,
        element("h3", t("获取途径", "Acquisition")), sources, element("small", card.id));
    dialog.showModal();
}

function normalize(value) {
    return value.normalize("NFKC").toLowerCase().replace(/[\s·_－-]+/g, "");
}

// Count a missing, mistyped or extra character, or a swapped adjacent pair.
function editDistance(a, b) {
    const rows = [Array.from({length: b.length + 1}, (_, j) => j)];
    for (let i = 1; i <= a.length; i++) {
        const row = [i];
        const prev = rows[i - 1];
        for (let j = 1; j <= b.length; j++) {
            row[j] = Math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + Number(a[i - 1] !== b[j - 1]));
            if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
                row[j] = Math.min(row[j], rows[i - 2][j - 2] + 1);
            }
        }
        rows.push(row);
    }
    return rows[a.length][b.length];
}

function relevance(row, term) {
    const {name, id} = row;
    if (name === term || id === term) return 1000;
    if (name.includes(term) || id.includes(term)) {
        const match = name.includes(term) ? name : id;
        return 800 + (match.startsWith(term) ? 50 : 0) - (match.length - term.length);
    }
    if (fuzzy.checked && term.length >= 2) {
        const limit = term.length >= 5 ? 2 : 1;
        let best = 0;
        for (const candidate of [name, id]) {
            if (Math.abs(term.length - candidate.length) > limit) continue;
            const distance = editDistance(term, candidate);
            if (distance <= limit) best = Math.max(best, 600 - 100 * distance - Math.abs(candidate.length - term.length));
        }
        if (best) return best;
    }
    if (row.tags.includes(term)) return 300;
    if (descriptions.checked && row.effect.includes(term)) return 200;
    if (descriptions.checked && row.sources.includes(term)) return 100;
    return 0;
}

function groupHeading(tag, title, size) {
    const heading = element(tag, title);
    heading.append(element("small", size + t(" 张", " cards")));
    return heading;
}

function makeGroup(title, matches, level = "h2") {
    const section = element("section", "", "spell-group");
    const grid = element("div", "", "spell-grid");
    grid.append(...matches.map(row => row.button));
    section.append(groupHeading(level, title, matches.length), grid);
    return section;
}

async function loadCatalog() {
    const response = await fetch(english ? "../catalog.en.json" : "catalog.json");
    if (!response.ok) throw new Error("catalog unavailable");
    const {cards, tags} = await response.json();
    for (const tag of [{id: "", text: t("全部标签", "All tags")}, ...tags]) {
        const label = element("label", undefined, "tag-option");
        const radio = document.createElement("input");
        radio.type = "radio";
        radio.name = "spell-tag";
        radio.value = tag.id;
        radio.setAttribute("form", "filters");
        radio.defaultChecked = tag.id === "";
        label.append(radio, element("span", tag.text));
        tagFilters.querySelector(".tag-options").append(label);
    }
    const categories = [...new Set(cards.map(card => card.category))];
    for (const value of categories) {
        category.add(new Option(value, value));
        const subgroups = new Set(cards.filter(card => card.category === value && card.subgroup).map(card => card.subgroup));
        if (subgroups.size) {
            const options = element("optgroup");
            options.label = value + t("细分", " subcategories");
            for (const sub of subgroups) options.append(new Option(sub, value + "/" + sub));
            category.append(options);
        }
    }
    for (const value of new Set(cards.map(card => card.station || noRecipe))) station.add(new Option(value, value));
    const rows = cards.map(card => {
        const button = element("button", undefined, "spell-card");
        button.type = "button";
        button.setAttribute("aria-haspopup", "dialog");
        button.append(icon(card), element("span", card.name));
        button.addEventListener("click", () => showCard(card));
        return {card, button, name: normalize(card.name), id: normalize(card.id),
            tags: [card.category, card.subgroup, card.rarity, ...card.tags].filter(Boolean).map(normalize).join(" "),
            effect: normalize(card.effect + " " + card.detailedEffect), sources: card.sources.map(normalize).join(" ")};
    });

    function render() {
        const term = normalize(query.value.trim());
        const selectedTag = tagFilters.querySelector("input:checked").value;
        const filtered = rows.filter(({card}) => (!category.value || category.value === card.category ||
            category.value === card.category + "/" + card.subgroup) &&
            (!station.value || station.value === (card.station || noRecipe)) &&
            (!selectedTag || card.tagIds.includes(selectedTag)));
        let groups;
        let total;
        if (term) {
            const ranked = filtered.map(row => ({row, score: relevance(row, term)}))
                .filter(hit => hit.score > 0).sort((a, b) => b.score - a.score);
            total = ranked.length;
            groups = total ? [makeGroup(t("搜索结果 · 按相关度", "Search results \u00b7 By relevance"), ranked.map(hit => hit.row))] : [];
        } else {
            total = filtered.length;
            groups = [];
            for (const kind of categories) {
                const group = filtered.filter(row => row.card.category === kind);
                if (!group.length) continue;
                if (group[0].card.subgroup) {
                    const parent = element("section", "", "spell-group spell-family");
                    parent.append(groupHeading("h2", kind, group.length));
                    for (const sub of new Set(group.map(row => row.card.subgroup))) {
                        parent.append(makeGroup(sub, group.filter(row => row.card.subgroup === sub), "h3"));
                    }
                    groups.push(parent);
                } else {
                    groups.push(makeGroup(kind, group));
                }
            }
        }
        entries.replaceChildren(...groups);
        count.textContent = total ? t("显示 ", "Showing ") + total + " / " + cards.length + t(" 张法术卡", " spell cards")
            : t("没有匹配的法术卡。试试缩短关键词或重置筛选。", "No matching spells. Try a shorter query or reset the filters.");
    }

    form.addEventListener("input", render);
    tagFilters.addEventListener("input", render);
    form.addEventListener("submit", event => event.preventDefault());
    form.addEventListener("reset", () => requestAnimationFrame(render));
    const requested = new URLSearchParams(location.search).get("card");
    const selected = rows.find(({card}) => card.id === requested);
    if (selected) query.value = selected.card.name;
    render();
    if (selected) {
        selected.button.focus();
        showCard(selected.card);
    }
}

document.querySelector("#close-detail").addEventListener("click", () => dialog.close());
function onBackdrop(event) {
    if (event.target !== dialog) return false;
    const bounds = dialog.getBoundingClientRect();
    return event.clientX < bounds.left || event.clientX >= bounds.right ||
        event.clientY < bounds.top || event.clientY >= bounds.bottom;
}

let pressedOnBackdrop = false;
dialog.addEventListener("pointerdown", event => { pressedOnBackdrop = onBackdrop(event); });
dialog.addEventListener("click", event => {
    if (pressedOnBackdrop && onBackdrop(event)) dialog.close();
    pressedOnBackdrop = false;
});
loadCatalog().catch(() => {
    count.textContent = t("图鉴未能载入。请通过本地 HTTP 地址打开，并刷新重试。", "Could not load the archive. Open it through a local HTTP server and refresh.");
});
