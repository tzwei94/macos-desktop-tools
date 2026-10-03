property managerName : "DisplayLink Manager"

on run
    try
        set managerPath to POSIX path of (path to application managerName)
    on error
        display alert "DisplayLink Manager is required" message "Install DisplayLink Manager from Synaptics, then open this toggle again. This utility does not include DisplayLink drivers." as warning
        return
    end try
    try
        if application managerName is running then
            tell application managerName to quit
        else
            do shell script "/usr/bin/open -a " & (quoted form of managerPath)
        end if
    on error errorMessage
        display alert "Could not toggle DisplayLink" message errorMessage as warning
    end try
end run
