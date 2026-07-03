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

; ==============================================================================
; GLOBAL CONTROL VARIABLES
; ==============================================================================
global IsMacroRunning := false

; ==============================================================================
; GUI
; ==============================================================================

MyGui := Gui("+Resize", "Breakfasts GAG2 Macro")
MyGui.BackColor := "101316"
LoadingText := MyGui.AddText("x0 y0 w500 h600 Center cWhite", "Loading macro panel...")
MyGui.OnEvent("Close", (*) => ExitApp())
MyGui.OnEvent("Size", OnGuiSize)
MyGui.Show("w500 h600")

WebView2.create(MyGui.Hwnd, OnWebInit)

; ==============================================================================
; HOTKEYS
; ==============================================================================

F1::ToggleMacroState()

; ==============================================================================
; INIT
; ==============================================================================

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

; ==============================================================================
; SEND STATE TO UI
; ==============================================================================

PushStateToUI() {
    global wv, IniPath

    if !wv
        return

    msg := "load"

    ; read config values
    nav := IniRead(IniPath, "Config", "NavigationKey", "")
    msg .= "|navKey=" nav
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

; ==============================================================================
; MESSAGE HANDLER
; ==============================================================================

OnWebMessage(sender, args) {
    global IniPath

    msg := args.TryGetWebMessageAsString()

    parts := StrSplit(msg, "|")
    cmd := parts[1]

    switch cmd {
        case "save":
            HandleSave(parts)

        case "start":
            ToggleMacroState()
    }
}

; ==============================================================================
; SAVE LOGIC
; ==============================================================================

HandleSave(parts) {
    global IniPath

    for i, item in parts {
        if i = 1
            continue

        if InStr(item, "navKey=") {
            IniWrite(StrReplace(item, "navKey=", ""), IniPath, "Config", "NavigationKey")
            continue
        }

        if InStr(item, "webhook=")
        {
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

; ==============================================================================
; MACRO STATE CONTROLLER & LOOPS
; ==============================================================================

ToggleMacroState() {
    global IsMacroRunning, wv
    
    if (IsMacroRunning) {
        ; Stop the macro execution
        IsMacroRunning := false
        if wv {
            wv.PostWebMessageAsString("macro:stopped")
            wv.PostWebMessageAsString("status:clear")
        }
        ToolTip("Macro Stopped")
        SetTimer(() => ToolTip(), -1500)
    } else {
        ; Start the macro routine
        IsMacroRunning := true
        if wv {
            wv.PostWebMessageAsString("macro:started")
        }
        ; Launch the loop on an independent asynchronous thread 
        SetTimer(StartMacroLoop, -10)
    }
}

StartMacroLoop() {
    global IsMacroRunning, wv

    ; 1. Run instantly the first time the start button is hit
    if (!IsMacroRunning)
        return
        
    ExecuteMacroSequence()
    
    ; 2. Continually verify system intervals to loop every 5th minute
    while (IsMacroRunning) {
        if wv {
            wv.PostWebMessageAsString("status:info|Waiting for the next 5-minute interval...")
        }
        
        ; Wait until the current minute is evenly divisible by 5 (e.g. :00, :05, :10)
        while (IsMacroRunning && Mod(A_Min, 5) != 0) {
            Sleep(1000)
        }
        
        ; Match perfect synchronicity at the top boundary (:00 seconds)
        while (IsMacroRunning && A_Sec != 0) {
            Sleep(500)
        }
        
        ; Stop intercept backup guard check
        if (!IsMacroRunning)
            break
            
        ExecuteMacroSequence()
        
        ; Sleep one minute to shift past the current target timestamp
        if (IsMacroRunning) {
            Sleep(60000) 
        }
    }
}

ExecuteMacroSequence() {
    global wv, IsMacroRunning
    KeepGuiVisible()
    
    if !ProcessExist("RobloxPlayerBeta.exe") {
        if wv {
            wv.PostWebMessageAsString("status:error|Roblox is not open! Please launch Roblox first.")
        }
        return
    }
    
    if !WinActive("ahk_exe RobloxPlayerBeta.exe") {
        WinActivate("ahk_exe RobloxPlayerBeta.exe")
    }
    
    if wv {
        wv.PostWebMessageAsString("status:clear")
    }

    EquipTrowel()
    if !IsMacroRunning
        return
    OpenSeedShop()
    if !IsMacroRunning
        return
    BuySeeds()
    if !IsMacroRunning
        return
    SendWebhook("Seed buying round completed successfully")
}

StartMacro() {
    ; Legacy method route mapping to dynamic framework controller
    ToggleMacroState()
}

RemoveToolTip:
    ToolTip
return

KeepGuiVisible() {
    global MyGui, Controller

    MyGui.Show("NoActivate")
    try Controller.IsVisible := true
    try Controller.Fill()
}

OpenSeedShop(){
    Align()
    Sleep(100)
    Send("{e}")
    Sleep(2000)
}

BuySeeds() {
     global IniPath, navkey, IsMacroRunning
    CenterMouseAndScrollUp(3000)
    if !IsMacroRunning
        return
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
        if !IsMacroRunning
            return

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
                if !IsMacroRunning {
                    ToolTip()
                    return
                }
                Sleep(50)
                Send("{Enter}")
                Sleep(50)
            }
            Sleep(200)
            Send("{Up}")
            Send("{Enter}")
            Sleep(200)
        } else {
            Sleep(200)
        }
    }
    ToolTip()

    if !IsMacroRunning
        return

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
    global IsMacroRunning
    MouseMove(A_ScreenWidth // 2, A_ScreenHeight // 2)

    endTime := A_TickCount + durationMs
    while A_TickCount < endTime {
        if !IsMacroRunning
            return
        Send("{WheelUp}")
        Sleep(50)
    }
}

ActivateRobloxPlayer(timeout := 5) {
    if !WinWait("ahk_exe RobloxPlayerBeta.exe", , timeout) {
        ToolTip("Roblox Player not found")
        SetTimer(() => ToolTip(), -1200)
        SendWebhook("❌ Error: Roblox Player window failed to open/load within timeout.")
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
    global IniPath, IsMacroRunning

    navKey := IniRead(IniPath, "Config", "NavigationKey", "")
    if navKey != "" {
        Send(navKey)
        Sleep(50)
    }

    if !IsMacroRunning
        return
    Send("{Up}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    if !IsMacroRunning
        return
    Send("{Right}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    if !IsMacroRunning
        return
    Send("{Left}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    if !IsMacroRunning
        return
    Send("{Right}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    if !IsMacroRunning
        return
    Send("{Left}")
    Sleep(150)
    Send("{Enter}")
    Sleep(150)
    if !IsMacroRunning
        return
    Send(navKey)
    Sleep(50)
    Send("{i down}")
    Sleep(3000)
    Send("{i up}")
    Sleep(50)
}

; ==============================================================================
; WEBHOOK HELPER
; ==============================================================================

SendWebhook(message) {
    global IniPath
    url := IniRead(IniPath, "Config", "WebhookLink", "")
    
    if (url = "" || InStr(url, "discord.com/api/webhooks") = 0)
        return
    
    safeMessage := StrReplace(message, '"', '\"')
    jsonPayload := '{"content": "' safeMessage '"}'
    
    try {
        http := ComObject("Msxml2.XMLHTTP")
        http.Open("POST", url, true)
        http.SetRequestHeader("Content-Type", "application/json")
        http.Send(jsonPayload)
    } catch {
        ToolTip("Webhook failed to send: " message)
        SetTimer(() => ToolTip(), -1500)
    }
}