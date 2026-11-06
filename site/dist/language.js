"use strict";
(() => {
    const key = "nw-guide-language";
    const url = new URL(location.href);
    const valid = value => ["auto", "zh", "en"].includes(value);
    let choice = url.searchParams.get("lang");
    try {
        if (valid(choice)) localStorage.setItem(key, choice);
        else choice = localStorage.getItem(key);
    } catch (_) { /* The URL remains usable when storage is unavailable. */ }
    if (!valid(choice)) choice = "auto";
    const language = choice === "auto"
        ? (/^zh\b/i.test((navigator.languages || [navigator.language])[0] || "en") ? "zh" : "en")
        : choice;
    const current = document.documentElement.lang === "en" ? "en" : "zh";
    function destination(selected) {
        const next = new URL(location.href);
        const base = next.pathname.replace(/\/en\/([^/]*)$/, "/$1");
        next.pathname = selected === "en" ? base.replace(/\/([^/]*)$/, "/en/$1") : base;
        return next;
    }
    if (language !== current) {
        const next = destination(language);
        next.searchParams.set("lang", choice);
        location.replace(next.href);
        return;
    }
    window.NWGuideLanguage = language;
    document.addEventListener("DOMContentLoaded", () => {
        const label = document.createElement("label");
        label.className = "language-picker";
        label.append(language === "en" ? "Language " : "语言 ");
        const select = document.createElement("select");
        for (const [value, title] of [["auto", "自动 / Auto"], ["zh", "中文"], ["en", "English"]]) {
            select.add(new Option(title, value, false, value === choice));
        }
        label.append(select);
        document.querySelector("header .top").append(label);
        select.addEventListener("change", () => {
            const next = new URL(location.href);
            next.searchParams.set("lang", select.value);
            location.assign(next.href);
        });
        for (const link of document.querySelectorAll('a[href*=".html"]')) {
            const next = new URL(link.href);
            if (next.origin === location.origin) {
                next.searchParams.set("lang", choice);
                link.href = next.href;
            }
        }
    });
})();
