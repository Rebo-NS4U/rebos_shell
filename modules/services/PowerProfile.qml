pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower as SystemPower
import qs.modules.theme

Singleton {
    id: root

    // Use the PPD D-Bus API directly, including tuned-ppd's implementation.
    // Bind to the system state so changes made elsewhere update every selector.
    readonly property list<string> availableProfiles: SystemPower.PowerProfiles.hasPerformanceProfile
        ? ["power-saver", "balanced", "performance"]
        : ["power-saver", "balanced"]
    readonly property string currentProfile: {
        switch (SystemPower.PowerProfiles.profile) {
        case SystemPower.PowerProfile.PowerSaver: return "power-saver";
        case SystemPower.PowerProfile.Balanced: return "balanced";
        case SystemPower.PowerProfile.Performance: return "performance";
        default: return "";
        }
    }

    signal profileChanged(string profile)
    onCurrentProfileChanged: {
        console.info("PowerProfile: Active profile:", currentProfile);
        profileChanged(currentProfile);
    }

    Component.onCompleted: Qt.callLater(() => {
        console.info("PowerProfile: Available profiles:", availableProfiles.join(", "), "active:", currentProfile);
    })

    function setProfile(profileName: string) {
        if (availableProfiles.indexOf(profileName) === -1)
            return;

        switch (profileName) {
        case "power-saver":
            SystemPower.PowerProfiles.profile = SystemPower.PowerProfile.PowerSaver;
            break;
        case "balanced":
            SystemPower.PowerProfiles.profile = SystemPower.PowerProfile.Balanced;
            break;
        case "performance":
            SystemPower.PowerProfiles.profile = SystemPower.PowerProfile.Performance;
            break;
        }
    }

    function getProfileIcon(profileName) {
        if (profileName === "power-saver")
            return Icons.powerSave;
        if (profileName === "balanced")
            return Icons.balanced;
        if (profileName === "performance")
            return Icons.performance;
        return Icons.balanced;
    }

    function getProfileDisplayName(profileName) {
        if (profileName === "power-saver")
            return "Power Save";
        if (profileName === "balanced")
            return "Balanced";
        if (profileName === "performance")
            return "Performance";
        return profileName;
    }
}
