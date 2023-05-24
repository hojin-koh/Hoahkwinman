; vim: fdm=marker
#SingleInstance Force
#NoEnv ; no empty variable check toward environment variables
#KeyHistory 0
#WinActivateForce
SetWorkingDir %A_ScriptDir%
SendMode Input ; seem to be faster

SetTitleMatchMode, RegEx
CoordMode, Mouse, Window

; For virtual desktop, VDA stands for Virtual Desktop Accessor
global hVDA := DllCall("LoadLibrary", "Str", A_ScriptDir . "\VirtualDesktopAccessor.dll", "Ptr")

global pGoToDesktopNumber := DllCall("GetProcAddress", Ptr, hVDA, AStr, "GoToDesktopNumber", "Ptr")
global pGetCurrentDesktopNumber := DllCall("GetProcAddress", Ptr, hVDA, AStr, "GetCurrentDesktopNumber", "Ptr")
global pGetDesktopCount := DllCall("GetProcAddress", Ptr, hVDA, AStr, "GetDesktopCount", "Ptr")
global pIsWindowOnDesktopNumber := DllCall("GetProcAddress", Ptr, hVDA, AStr, "IsWindowOnDesktopNumber", "Ptr")

global pIsPinnedWindow := DllCall("GetProcAddress", Ptr, hVDA, AStr, "IsPinnedWindow", "Ptr")
global pPinWindow := DllCall("GetProcAddress", Ptr, hVDA, AStr, "PinWindow", "Ptr")
global pUnPinWindow := DllCall("GetProcAddress", Ptr, hVDA, AStr, "UnPinWindow", "Ptr")

; Storing active window on each desktop
global mActiveWindowInDesktop := Object()

; For mouse emulation
global mIsMouseOn := Object()

; Initial desktop change
switchToDesktop(1, true)

if (A_Args.Length() > 0) {
  global keyShutdown := A_Args[1]
  OnClipboardChange("ClipChanged")
}

#Persistent

ClipChanged(Type) {
  if (Type == 1) {
    if (clipboard == keyShutdown) {
      ExitApp
    }
  }
}

RemoveToolTip:
  SetTimer, RemoveToolTip, Off
  ToolTip
return

#!F9::reload

; Virtual Desktop {{{
; Mostly copied from virtual-desktop-enhancer

getCurrentWindowID() {
  WinGet, _hActive, ID, A
  return _hActive
}

switchToDesktop(n:=1, forced:=false) {
  deskCurrent := DllCall(pGetCurrentDesktopNumber) + 1
  if (deskCurrent == n && ! forced) {
    return
  }
  if (n > DllCall(pGetDesktopCount)) {
    MsgBox, Desktop number %n% is out of range
    return
  }

  ; Before switch, record the active window
  mActiveWindowInDesktop[deskCurrent] := getCurrentWindowID()

  DllCall(pGoToDesktopNumber, Int, n-1)
  Menu, Tray, Icon, %n%.ico

  ; After switch, if the previously active window is still there, focus it
  ; Otherwise, just focus on the taskbar
  hWindowNew := mActiveWindowInDesktop[n]
  if (DllCall(pIsWindowOnDesktopNumber, UInt, hWindowNew, UInt, n-1) || DllCall(pIsPinnedWindow, UInt, hWindowNew)) {
    WinActivate, ahk_id %hWindowNew%
  } else {
    WinActivate, ahk_class Shell_TrayWnd
  }
}

#\::
hActive := getCurrentWindowID()
if (DllCall(pIsPinnedWindow, UInt, hActive)) {
  DllCall(pUnPinWindow, UInt, hActive)
  Tooltip, Unpinned, 0, 0
} else {
  DllCall(pPinWindow, UInt, hActive)
  Tooltip, Pinned, 0, 0
}
SetTimer, RemoveToolTip, 500
return

#1::switchToDesktop(1)
#2::switchToDesktop(2)
#3::switchToDesktop(3)
#4::switchToDesktop(4)

; }}}

; General window operations {{{

#m::
WinGet MX, MinMax, A
If MX = 1
  PostMessage, 0x112, 0xF120,,, A ; Restore
Else PostMessage, 0x112, 0xF030,,, A ; Maximize
return

#n::PostMessage, 0x112, 0xF020,,, A ; Minimize

; These two are copied from https://autohotkey.com/docs/scripts/EasyWindowDrag_(KDE).htm
#LButton::
CoordMode, Mouse ; Temporarily switch to screen mode
ToolTip, Window draggin mode, 0, 0
; Get the initial mouse position and window id, and
; abort if the window is maximized.
MouseGetPos,KDE_X1,KDE_Y1,KDE_id
WinGet,KDE_Win,MinMax,ahk_id %KDE_id%
If KDE_Win
  PostMessage, 0x112, 0xF120,,, ahk_id %KDE_id% ; Restore
; Get the initial window position.
WinGetPos,KDE_WinX1,KDE_WinY1,,,ahk_id %KDE_id%
Loop
{
  GetKeyState,KDE_Button,LButton,P ; Break if button has been released.
  If KDE_Button = U
    break
  MouseGetPos,KDE_X2,KDE_Y2 ; Get the current mouse position.
  KDE_X2 -= KDE_X1 ; Obtain an offset from the initial mouse position.
  KDE_Y2 -= KDE_Y1
  KDE_WinX2 := (KDE_WinX1 + KDE_X2) ; Apply this offset to the window position.
  KDE_WinY2 := (KDE_WinY1 + KDE_Y2)
  WinMove,ahk_id %KDE_id%,,%KDE_WinX2%,%KDE_WinY2% ; Move the window to the new position.
}
CoordMode, Mouse, Window ; Restore the setting
Tooltip
return

#RButton::
CoordMode, Mouse ; Temporarily switch to screen mode
ToolTip, Window resize mode, 0, 0
; Get the initial mouse position and window id, and
; abort if the window is maximized.
MouseGetPos,KDE_X1,KDE_Y1,KDE_id
WinGet,KDE_Win,MinMax,ahk_id %KDE_id%
If KDE_Win
  PostMessage, 0x112, 0xF120,,, ahk_id %KDE_id% ; Restore
; Get the initial window position and size.
WinGetPos,KDE_WinX1,KDE_WinY1,KDE_WinW,KDE_WinH,ahk_id %KDE_id%
; Define the window region the mouse is currently in.
; The four regions are Up and Left, Up and Right, Down and Left, Down and Right.
If (KDE_X1 < KDE_WinX1 + KDE_WinW / 2)
  KDE_WinLeft := 1
Else
  KDE_WinLeft := -1
If (KDE_Y1 < KDE_WinY1 + KDE_WinH / 2)
  KDE_WinUp := 1
Else
  KDE_WinUp := -1
Loop
{
  GetKeyState,KDE_Button,RButton,P ; Break if button has been released.
  If KDE_Button = U
    break
  MouseGetPos,KDE_X2,KDE_Y2 ; Get the current mouse position.
  ; Get the current window position and size.
  WinGetPos,KDE_WinX1,KDE_WinY1,KDE_WinW,KDE_WinH,ahk_id %KDE_id%
  KDE_X2 -= KDE_X1 ; Obtain an offset from the initial mouse position.
  KDE_Y2 -= KDE_Y1
  ; Then, act according to the defined region.
  WinMove,ahk_id %KDE_id%,, KDE_WinX1 + (KDE_WinLeft+1)/2*KDE_X2  ; X of resized window
              , KDE_WinY1 +   (KDE_WinUp+1)/2*KDE_Y2  ; Y of resized window
              , KDE_WinW  -   KDE_WinLeft  *KDE_X2  ; W of resized window
              , KDE_WinH  -     KDE_WinUp  *KDE_Y2  ; H of resized window
  KDE_X1 := (KDE_X2 + KDE_X1) ; Reset the initial position for the next iteration.
  KDE_Y1 := (KDE_Y2 + KDE_Y1)
}
CoordMode, Mouse, Window ; Restore the setting
Tooltip
return

; Switch titlebar
#`;::
WinGet Style, Style, A
if (Style & 0xC40000) {
  WinSet, Style, -0xC40000, A
  Tooltip, Title bar switched off, 0, 0
} else {
  WinSet, Style, +0xC40000, A
  Tooltip, Title bar switched on, 0, 0
}
SetTimer, RemoveToolTip, 500
return

; Change transparency
#[::
WinGet, Trans, Transparent, A
if (Trans = "")
  Trans := 255
if (Trans - 20 <= 40)
  Trans := 40
else
  Trans -= 20
Tooltip, Opacity level %Trans%, 0, 0
SetTimer, RemoveToolTip, 500
WinSet, Transparent, %Trans%, A
return

#]::
WinGet, Trans, Transparent, A
if (Trans = "")
  Trans := 255
if (Trans + 20 >= 255)
  Trans := "Off"
else
  Trans += 20
Tooltip, Opacity level %Trans%, 0, 0
SetTimer, RemoveToolTip, 500
WinSet, Transparent, %Trans%, A
return

; }}}

; Mouse Emulation {{{
#UseHook

ActionClick:
  click
return
ActionClickRight:
  click right
return
ActionClickDown:
  if GetKeyState("LButton") = 0 {
    click down
  }
return
ActionClickUp:
  if GetKeyState("LButton") = 1 {
    click up
  }
return
ActionClickRightDown:
  if GetKeyState("RButton") = 0 {
    click right down
  }
return
ActionClickRightUp:
  if GetKeyState("RButton") = 1 {
    click right up
  }
return

#!m::
WinGet, WinID, ID, A
Hotkey, IfWinActive, ahk_id %WinID%
if (mIsMouseOn[WinID] = true) {
  Hotkey, *`;    ,, Off
  Hotkey, *'     ,, Off
  Hotkey, *[     ,, Off
  Hotkey, *[ UP  ,, Off
  Hotkey, *]     ,, Off
  Hotkey, *] UP  ,, Off
  mIsMouseOn[WinID] := false
  ToolTip, Mouse emulation on %WinID% is turned off, 0, 0

} else {
  Hotkey, *`;    , ActionClick, On
  Hotkey, *'     , ActionClickRight, On
  Hotkey, *[     , ActionClickDown, On
  Hotkey, *[ UP  , ActionClickUp, On
  Hotkey, *]     , ActionClickRightDown, On
  Hotkey, *] UP  , ActionClickRightUp, On
  mIsMouseOn[WinID] := true
  ToolTip, Mouse emulation on %WinID% is turned on, 0, 0
}
Hotkey, IfWinActive
SetTimer, RemoveToolTip, 1000
return

#!n::
Hotkey, IfWinActive,
if (mIsMouseOn["global"] = true) {
  Hotkey, *`;    ,, Off
  Hotkey, *'     ,, Off
  Hotkey, *[     ,, Off
  Hotkey, *[ UP  ,, Off
  Hotkey, *]     ,, Off
  Hotkey, *] UP  ,, Off
  mIsMouseOn["global"] := false
  ToolTip, Mouse emulation (global) is turned off, 0, 0

} else {
  Hotkey, *`;    , ActionClick, On
  Hotkey, *'     , ActionClickRight, On
  Hotkey, *[     , ActionClickDown, On
  Hotkey, *[ UP  , ActionClickUp, On
  Hotkey, *]     , ActionClickRightDown, On
  Hotkey, *] UP  , ActionClickRightUp, On
  mIsMouseOn["global"] := true
  ToolTip, Mouse emulation (global) is turned on, 0, 0
}
SetTimer, RemoveToolTip, 1000
return

; }}}
