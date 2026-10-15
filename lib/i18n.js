// Translations for the standalone QML apps (picker, studio, talk overlay): same catalogs as lib/i18n.py.
// Usage in QML:  import "i18n.js" as I18n
//                function tr(text, ...args) { return I18n.tr(Qt.resolvedUrl("locale/"), text, args) }
// Needs QML_XHR_ALLOW_FILE_READ=1 (set by the plasmarchy script).
.pragma library

var catalog = null

function load(dir) {
    catalog = {}
    var full = Qt.locale().name                 // e.g. "pt_BR"
    var names = [full.split("_")[0], full]      // general catalog first, regional entries override
    for (var i = 0; i < names.length; i++) {
        if (!names[i] || names[i] === "en" || names[i] === "C" || (i === 1 && names[1] === names[0]))
            continue
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", dir + names[i] + ".json", false)   // synchronous: tiny local file, needed for the first binding
            xhr.send()
            if (xhr.responseText) {
                var part = JSON.parse(xhr.responseText)
                for (var k in part) catalog[k] = part[k]
            }
        } catch (e) {}
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
