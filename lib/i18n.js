// Translations for the standalone QML apps (picker, studio, talk overlay): same catalogs as lib/i18n.py.
// Usage in QML:  import "i18n.js" as I18n
//                function tr(text, ...args) { return I18n.tr(Qt.resolvedUrl("locale/"), text, args) }
// Needs QML_XHR_ALLOW_FILE_READ=1 (set by the plasmarchy script).
.pragma library

var catalog = null

function load(dir) {
    catalog = {}
    var lang = Qt.locale().name.split("_")[0]
    if (!lang || lang === "en" || lang === "C")
        return
    try {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", dir + lang + ".json", false)   // synchronous: tiny local file, needed for the first binding
        xhr.send()
        if (xhr.responseText)
            catalog = JSON.parse(xhr.responseText)
    } catch (e) {
        catalog = {}
    }
}

function tr(dir, text, args) {
    if (catalog === null)
        load(dir)
    var s = catalog[text] || text
    for (var i = 0; i < (args ? args.length : 0); i++)
        s = s.split("{" + i + "}").join(String(args[i]))
    return s
}
