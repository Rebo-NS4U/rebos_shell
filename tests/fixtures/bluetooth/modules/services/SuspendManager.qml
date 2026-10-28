pragma Singleton
import Quickshell
Singleton {
    property bool isSuspending: false
    signal preparingForSleep()
    signal wakingUp()
}
