on run args
    set controller to load script POSIX file (item 1 of args)
    set controller's preferencesDomain to item 2 of args
    set controller's defaultsExecutable to item 3 of args
    set operation to item 4 of args
    if operation is "validate" then
        return controller's validatedSpacing(item 5 of args)
    else if operation is "apply" then
        controller's applySpacing(item 5 of args)
        return "applied"
    else if operation is "restore" then
        controller's restoreDefaults()
        return "restored"
    else if operation is "read" then
        set snapshot to controller's readPreference(item 5 of args)
        if not (isPresent of snapshot) then return "absent"
        return (storedType of snapshot) & ":" & (storedValue of snapshot)
    else if operation is "initial-input" then
        return controller's initialInputText(controller's readPreference(controller's spacingKey))
    end if
    error "Unknown operation"
end run
