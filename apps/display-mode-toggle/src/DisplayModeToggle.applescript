on bundledHelperPath()
    -- NSAppleScript's path to me is the compiled script, not the app bundle.
    set scriptPath to POSIX path of (path to me)
    set scriptDirectory to do shell script "/usr/bin/dirname " & quoted form of scriptPath
    return scriptDirectory & "/../display-mode"
end bundledHelperPath

on run
    try
        set helperPath to bundledHelperPath()
        set newMode to do shell script (quoted form of helperPath) & " toggle"
        if newMode is "mirror" then
            set messageText to "External displays now mirror the main display."
            set subtitleText to "Mirror enabled"
        else if newMode is "extend-left" then
            set messageText to "External displays now extend to the left of the main display."
            set subtitleText to "Extend left enabled"
        else
            error "The display helper returned an unexpected result."
        end if
        try
            display notification messageText with title "Display Mode" subtitle subtitleText
        end try
    on error errorMessage
        display alert "Could not change display mode" message errorMessage as warning
    end try
end run
