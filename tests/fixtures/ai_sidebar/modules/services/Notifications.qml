pragma Singleton
import Quickshell

Singleton {
    property list<var> list: []
    property int nextId: 1
    property int sentCount: 0

    function notifyInternal(options) {
        list = list.filter(item => item.replaceKey !== options.replaceKey);
        let notification = Object.assign({id: nextId++}, options);
        list = list.concat([notification]);
        sentCount++;
        return notification;
    }

    function discardNotifications(ids) {
        list = list.filter(item => !ids.includes(item.id));
    }
}
