import Quickshell
pragma Singleton

Singleton {
    property bool initialized: true
    signal stateLoaded()

    function set(k, v) {
    }

    function get(k, v) {
        return v;
    }

}
