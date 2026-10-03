property preferencesDomain : "-g"
property defaultsExecutable : "/usr/bin/defaults"
property spacingKey : "NSStatusItemSpacing"
property paddingKey : "NSStatusItemSelectionPadding"

on run
    my showSettings()
end run

on displayValue(snapshot)
    if not (isPresent of snapshot) then return "System default"
    if storedType of snapshot is "integer" then return storedValue of snapshot
    return "Custom value (" & (storedType of snapshot) & ")"
end displayValue

on initialInputText(snapshot)
    if isPresent of snapshot and storedType of snapshot is "integer" then
        try
            return (my validatedSpacing(storedValue of snapshot)) as text
        end try
    end if
    return "3"
end initialInputText

on showSettings()
    set inputText to missing value
    activate
    repeat
        try
            set spacingSnapshot to my readPreference(spacingKey)
            if inputText is missing value then set inputText to my initialInputText(spacingSnapshot)
            set currentSpacing to my displayValue(spacingSnapshot)
            set currentPadding to my displayValue(my readPreference(paddingKey))
            set promptText to "Current spacing: " & currentSpacing & linefeed & "Current selection padding: " & currentPadding & linefeed & linefeed & "Choose a whole number from 0 to 32." & linefeed & "Smaller values bring menu bar icons closer together."
            set response to display dialog promptText with title "Menu Bar Spacing" default answer inputText buttons {"Restore Defaults", "Cancel", "Apply"} default button "Apply" cancel button "Cancel"
            set selectedButton to button returned of response
            set inputText to text returned of response
            if selectedButton is "Apply" then
                try
                    my validatedSpacing(inputText)
                on error
                    display alert "Enter a whole number from 0 to 32" message "No settings were changed. Correct the value and try again." as warning
                    set selectedButton to "Invalid"
                end try
            end if
            if selectedButton is "Apply" then
                my applySpacing(inputText)
                my showConfirmation("Spacing and selection padding are now set to " & ((my validatedSpacing(inputText)) as text) & ".")
                return
            else if selectedButton is "Restore Defaults" then
                my restoreDefaults()
                my showConfirmation("The spacing and padding overrides have been removed.")
                return
            end if
        on error errorText number errorNumber
            if errorNumber is -128 then return
            display alert "Could not change menu bar spacing" message errorText as warning
            return
        end try
    end repeat
end showSettings

on showConfirmation(messageText)
    display alert "Menu bar settings saved" message (messageText & linefeed & linefeed & "To see the change everywhere, reopen your menu bar apps or sign out and back in when convenient.") as informational
end showConfirmation

on validatedSpacing(inputText)
    set inputText to inputText as text
    if (length of inputText) is 0 or (length of inputText) > 2 then error "Enter a whole number from 0 to 32."
    repeat with digit in characters of inputText
        if "0123456789" does not contain (digit as text) then error "Enter a whole number from 0 to 32."
    end repeat
    set spacing to inputText as integer
    if spacing > 32 then error "Enter a whole number from 0 to 32."
    return spacing
end validatedSpacing

on preferenceCommand(operation, whichKey)
    return (quoted form of defaultsExecutable) & " -currentHost " & operation & " " & (quoted form of preferencesDomain) & " " & (quoted form of whichKey)
end preferenceCommand

on readPreference(whichKey)
    try
        set typeDescription to do shell script my preferenceCommand("read-type", whichKey) altering line endings false
    on error errorText number errorNumber
        if errorNumber is 1 and (errorText contains "does not exist" or errorText contains "Could not find key" or (errorText contains "Error: Domain '" and errorText contains "not found.")) then
            return {isPresent:false, storedType:"", storedValue:""}
        end if
        error errorText number errorNumber
    end try
    set typeName to last word of typeDescription
    if {"array", "dictionary", "data"} contains typeName then
        -- Human-readable compound values lose nested types and can truncate data.
        -- Keep the complete typed plist for verification and rollback.
        set exportCommand to (quoted form of defaultsExecutable) & " -currentHost export " & (quoted form of preferencesDomain) & " -"
        set extractCommand to exportCommand & " | /usr/bin/plutil -extract " & (quoted form of whichKey) & " xml1 -o - -"
        set savedText to do shell script "/bin/bash -o pipefail -c " & (quoted form of extractCommand) altering line endings false
    else
        set savedText to do shell script my preferenceCommand("read", whichKey) altering line endings false
    end if
    -- defaults appends one linefeed; retain any linefeeds in the stored string.
    if savedText ends with linefeed then
        if length of savedText is 1 then
            set savedText to ""
        else
            set savedText to text 1 thru -2 of savedText
        end if
    end if
    return {isPresent:true, storedType:typeName, storedValue:savedText}
end readPreference

on samePreference(firstValue, secondValue)
    if (isPresent of firstValue) is not (isPresent of secondValue) then return false
    if not (isPresent of firstValue) then return true
    return (storedType of firstValue) is (storedType of secondValue) and (storedValue of firstValue) is (storedValue of secondValue)
end samePreference

on ensureRestorable(snapshot)
    if not (isPresent of snapshot) then return
    if {"integer", "float", "boolean", "string", "array", "dictionary", "data"} does not contain (storedType of snapshot) then
        error "The existing preference has an unsupported type. No settings were changed."
    end if
end ensureRestorable

on writeSnapshot(whichKey, snapshot)
    set currentValue to my readPreference(whichKey)
    if my samePreference(currentValue, snapshot) then return
    if not (isPresent of snapshot) then
        do shell script my preferenceCommand("delete", whichKey)
    else
        set typeName to storedType of snapshot
        set valueText to storedValue of snapshot
        if typeName is "integer" then
            set typeFlag to " -int "
        else if typeName is "float" then
            set typeFlag to " -float "
        else if typeName is "boolean" then
            set typeFlag to " -bool "
        else if typeName is "string" then
            set typeFlag to " -string "
        else
            -- defaults parses the typed XML property list without losing nested types.
            set typeFlag to " "
        end if
        do shell script (my preferenceCommand("write", whichKey)) & typeFlag & (quoted form of valueText)
    end if
    if not my samePreference(my readPreference(whichKey), snapshot) then error "Could not verify the saved preference " & whichKey & "."
end writeSnapshot

on changeSettings(targetValue)
    set originalSpacing to my readPreference(spacingKey)
    set originalPadding to my readPreference(paddingKey)
    my ensureRestorable(originalSpacing)
    my ensureRestorable(originalPadding)
    try
        my writeSnapshot(spacingKey, targetValue)
        my writeSnapshot(paddingKey, targetValue)
        -- Verify the pair together before reporting success.
        if not my samePreference(my readPreference(spacingKey), targetValue) then error "Could not verify spacing."
        if not my samePreference(my readPreference(paddingKey), targetValue) then error "Could not verify selection padding."
    on error changeError
        set rollbackErrors to ""
        try
            my writeSnapshot(spacingKey, originalSpacing)
        on error rollbackError
            set rollbackErrors to rollbackErrors & spacingKey & ": " & rollbackError & linefeed
        end try
        try
            my writeSnapshot(paddingKey, originalPadding)
        on error rollbackError
            set rollbackErrors to rollbackErrors & paddingKey & ": " & rollbackError & linefeed
        end try
        if rollbackErrors is not "" then
            error "The change failed: " & changeError & linefeed & linefeed & "Rollback could not restore all settings:" & linefeed & rollbackErrors
        end if
        error "The change failed. Previous settings were restored." & linefeed & changeError
    end try
end changeSettings

on applySpacing(inputText)
    set spacing to my validatedSpacing(inputText)
    my changeSettings({isPresent:true, storedType:"integer", storedValue:spacing as text})
end applySpacing

on restoreDefaults()
    my changeSettings({isPresent:false, storedType:"", storedValue:""})
end restoreDefaults
