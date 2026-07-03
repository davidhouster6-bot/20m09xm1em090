#Requires AutoHotkey v2.0
#SingleInstance Force
#Include WebView2\WebView2.ahk

global wv, Controller, MyGui, LoadingText, WebMessageHandler, DomLoadedHandler, ProcessFailedHandler
global IniPath := A_ScriptDir "\Config.ini"
global navkey := IniRead(IniPath, "Config", "NavigationKey", "")

if navkey = ""
{
    MsgBox("Navigation key not set. Please set it in the GUI")
    ExitApp()
}

; =========================
; GUI
; =========================

MyGui := Gui("+Resize +AlwaysOnTop", "Breakfasts GAG2 Macro")
MyGui.BackColor := "101316"
LoadingText := MyGui.AddText("x0 y0 w500 h600 Center cWhite", "Loading macro panel...")
MyGui.OnEvent("Close", (*) => ExitApp())
MyGui.OnEvent("Size", OnGuiSize)
MyGui.Show("w500 h600")

WebView2.create(MyGui.Hwnd, OnWebInit)

; =========================
; INIT
; =========================

OnWebInit(ctrl) {
    global wv, Controller, MyGui, LoadingText, WebMessageHandler, DomLoadedHandler, ProcessFailedHandler

    Controller := ctrl
    wv := ctrl.CoreWebView2
    try LoadingText.Visible := false

    WebMessageHandler := wv.WebMessageReceived(OnWebMessage)
    DomLoadedHandler := wv.DOMContentLoaded(OnDomLoaded)
    ProcessFailedHandler := wv.ProcessFailed(OnWebProcessFailed)

    LoadPanelHtml()

    ; fallback in case the page load event is missed
    SetTimer(PushStateToUI, -800)
}

OnDomLoaded(sender, args) {
    PushStateToUI()
}

OnWebProcessFailed(sender, args) {
    SetTimer(LoadPanelHtml, -250)
}

OnGuiSize(guiObj, minMax, width, height) {
    global Controller, LoadingText

    try LoadingText.Move(0, 0, width, height)
    try Controller.Fill()
}

LoadPanelHtml() {
    global wv

    if !wv
        return

    htmlPath := A_ScriptDir "\webview.html"
    wv.NavigateToString(FileRead(htmlPath, "UTF-8"))
}

; =========================
; SEND STATE TO UI
; =========================

PushStateToUI() {
    global wv, IniPath

    if !wv
        return

    msg := "load"

    ; read config values
    nav := IniRead(IniPath, "Config", "NavigationKey", "")
    msg .= "|navKey=" nav
    msg .= "|privateServer=" IniRead(IniPath, "Config", "PrivateServerLink", "")
    msg .= "|webhook=" IniRead(IniPath, "Config", "WebhookLink", "")

    for seed in ReadOrderedIniValues(IniPath, "Seeds") {
        val := IniRead(IniPath, "SeedSelections", seed, "0")
        msg .= "|seed:" seed "=" val
    }

    for gear in ReadOrderedIniValues(IniPath, "Gears") {
        val := IniRead(IniPath, "GearSelections", gear, "0")
        msg .= "|gear:" gear "=" val
    }

    wv.PostWebMessageAsString(msg)
}

ReadOrderedIniValues(path, section) {
    items := []

    try {
        sectionText := IniRead(path, section)
    } catch {
        return items
    }

    for line in StrSplit(sectionText, "`n", "`r") {
        if !InStr(line, "=")
            continue

        parts := StrSplit(line, "=", , 2)
        if parts.Length = 2 && parts[2] != ""
            items.Push(parts[2])
    }

    return items
}

; =========================
; MESSAGE HANDLER
; =========================

OnWebMessage(sender, args) {
    global IniPath

    msg := args.TryGetWebMessageAsString()

    parts := StrSplit(msg, "|")
    cmd := parts[1]

    switch cmd {
        case "save":
            HandleSave(parts)

        case "start":
            StartMacro()
    }
}

; =========================
; SAVE LOGIC
; =========================

HandleSave(parts) {
    global IniPath

    for i, item in parts {
        if i = 1
            continue

        if InStr(item, "navKey=") {
            IniWrite(StrReplace(item, "navKey=", ""), IniPath, "Config", "NavigationKey")
            continue
        }

        if InStr(item, "privateServer=") {
            IniWrite(StrReplace(item, "privateServer=", ""), IniPath, "Config", "PrivateServerLink")
            continue
        }

        if InStr(item, "webhook=") {
            IniWrite(StrReplace(item, "webhook=", ""), IniPath, "Config", "WebhookLink")
            continue
        }

        itemParts := StrSplit(item, ":", , 2)
        if itemParts.Length < 2
            continue

        itemType := itemParts[1]
        kv := StrSplit(itemParts[2], "=", , 2)
        if kv.Length < 2
            continue

        key := kv[1]
        val := kv[2]

        switch itemType {
            case "seed":
                IniWrite(val, IniPath, "SeedSelections", key)

            case "gear":
                IniWrite(val, IniPath, "GearSelections", key)
        }
    }

    ToolTip("Saved")
    SetTimer(() => ToolTip(), -800)
}

; =========================
; MACRO
; =========================

StartMacro() {
    global IniPath
    KeepGuiVisible()

    if !ProcessExist("RobloxPlayerBeta.exe") {
        link := IniRead(IniPath, "Config", "PrivateServerLink", "")
        Run(link != "" ? link : "roblox://")
        ActivateRobloxPlayer(30)
        return
    }

    if !ActivateRobloxPlayer()
        return

    EquipTrowel()
    OpenSeedShop()
    BuySeeds()
}

KeepGuiVisible() {
    global MyGui, Controller

    MyGui.Opt("+AlwaysOnTop")
    MyGui.Show("NoActivate")
    try Controller.IsVisible := true
    try Controller.Fill()
}

OpenSeedShop(){
    Align()
    Sleep(100)
    Send("{e}")
    Sleep(2000)
        ; check for this color  here #67D147, if not found, rejoin private server
}

BuySeeds() {
    global IniPath, navkey
    CenterMouseAndScrollUp(3000)
    Send(navkey)
    Sleep(100)
    Send("{Right}")
    Sleep(100)
    Send("{Right}")
    Sleep(100)
    Send("{Right}")
    Sleep(100)
    Send("{Left}")
    Sleep(100)
    Send("{Down}")
    Sleep(100)
    Send("{Down}")
    Sleep(100)



    firstSeed := true
    for seed in ReadOrderedIniValues(IniPath, "Seeds") {
        if firstSeed {
            firstSeed := false
        } else {
            Send("{Down}")
            Sleep(200)
        }

        isSelected := IniRead(IniPath, "SeedSelections", seed, "0")
        ToolTip("Seed: " seed "`nSelected: " (isSelected = "1" ? "Yes" : "No"))

        if isSelected = "1" {
            Sleep(200)
            Send("{Enter}")
            Sleep(200)
            Send("{Down}")
            Sleep(200)

            Loop 15 {
                Sleep(50)
                Send("{Enter}")
                Sleep(50)
            }
            Sleep(200)
            Send("{Up}")
            Sleep(200)
            Send("{Enter}")
            Sleep(200)
        } else {
            Sleep(200)
        }

    }
    ToolTip()
    Sleep(100)
    Send(navkey)
    Sleep(100)
    Send(navkey)
    Sleep(100)
    Send("{Left}")
    Sleep(100)
    Send("{Enter}")
    Sleep(100)
    Send(navkey)
    Sleep(100)
}


CenterMouseAndScrollUp(durationMs := 3000) {
    MouseMove(A_ScreenWidth // 2, A_ScreenHeight // 2)

    endTime := A_TickCount + durationMs
    while A_TickCount < endTime {
        Send("{WheelUp}")
        Sleep(50)
    }
}

ActivateRobloxPlayer(timeout := 5) {
    if !WinWait("ahk_exe RobloxPlayerBeta.exe", , timeout) {
        ToolTip("Roblox Player not found")
        SetTimer(() => ToolTip(), -1200)
        return false
    }

    WinActivate("ahk_exe RobloxPlayerBeta.exe")
    return WinWaitActive("ahk_exe RobloxPlayerBeta.exe", , 5)
}

EquipTrowel() {
    Sleep(100)
    Send("1")
    Sleep(50)
    Send("2")
    Sleep(50)
    Send("3")
}

Align() {
    global IniPath

    navKey := IniRead(IniPath, "Config", "NavigationKey", "")
    if navKey != "" {
        Send(navKey)
        Sleep(50)
    }

    Send("{Up}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    Send("{Right}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    Send("{Left}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    Send("{Right}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    Send("{Left}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    Send(navKey)
    Sleep(50)
    Send("{i down}")
    Sleep(3000)
    Send("{i up}")
    Sleep(50)

}
