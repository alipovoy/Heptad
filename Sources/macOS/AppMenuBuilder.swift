import Cocoa

struct AppMenuBuilder {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About 7Notes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit 7Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Format menu
        let formatMenuItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")

        let fontMenuItem = NSMenuItem()
        let fontMenu = NSMenu(title: "Font")

        let boldItem = fontMenu.addItem(withTitle: "Bold", action: #selector(NSFontManager.addFontTrait(_:)), keyEquivalent: "b")
        boldItem.tag = Int(NSFontTraitMask.boldFontMask.rawValue)

        let italicItem = fontMenu.addItem(withTitle: "Italic", action: #selector(NSFontManager.addFontTrait(_:)), keyEquivalent: "i")
        italicItem.tag = Int(NSFontTraitMask.italicFontMask.rawValue)

        fontMenu.addItem(.separator())

        let biggerItem = fontMenu.addItem(withTitle: "Bigger", action: #selector(NSFontManager.modifyFont(_:)), keyEquivalent: "+")
        biggerItem.tag = 3 // NSSizeUpFontAction

        let smallerItem = fontMenu.addItem(withTitle: "Smaller", action: #selector(NSFontManager.modifyFont(_:)), keyEquivalent: "-")
        smallerItem.tag = 4 // NSSizeDownFontAction

        fontMenuItem.submenu = fontMenu
        formatMenu.addItem(fontMenuItem)

        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        return mainMenu
    }
}
