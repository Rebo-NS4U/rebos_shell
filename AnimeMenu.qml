pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Wayland._BackgroundEffect
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.modules.widgets.dashboard.controls

PanelWindow {
    id: root

    property bool opened: false
    property bool backendStarted: false
    property bool ready: false
    property bool loading: false
    property bool detailLoading: false
    property bool hasMore: true
    property bool loadFailed: false
    property int requestId: 0
    property int detailRequest: 0
    property int cataloguePage: 1
    property string mediaKind: "anime"
    readonly property bool isYoutube: mediaKind === "youtube"
    readonly property string mediaName: ({anime: "Anime", movies: "Movies", tv: "TV", youtube: "YouTube"})[mediaKind]
    property var tabStates: ({})
    property string pageView: "browse"
    property string previousPage: "browse"
    property string query: ""
    property string category: "most-popular"
    property string message: "Choose a show to see its details"
    property string playback: ""
    property bool playbackPaused: false
    property string captionStatus: ""
    property bool subtitlesOff: true
    property bool whisperSelected: false
    readonly property bool captionsEnabled: (settings.live_subtitles ?? true) && whisperSelected && !subtitlesOff
    property var selectedShow: ({})
    property var details: ({})
    property var settings: ({})
    property var torbox: ({connected: false, text: "TorBox is not connected."})
    property bool torboxBusy: false
    property bool torboxManual: false
    property var youtubeRecommendations: []
    property list<string> mediaGenres: []
    property var filterOptions: []
    property var appliedFilters: ({})
    property var draftFilters: ({})
    readonly property int filterCount: Object.values(appliedFilters).filter(value => value !== "").length
    property list<string> episodes: []
    property int selectedEpisode: 0
    readonly property real unit: Styling.fontSize(0)
    property string screenName: ""

    screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
    readonly property bool active: opened && !GlobalStates.lockscreenVisible
    property real slideProgress: active ? 1 : 0
    readonly property bool presented: active || slideProgress > 0 || slideAnimation.running
    Behavior on slideProgress {
        enabled: Motion.enabled && !GlobalStates.lockscreenVisible
        NumberAnimation {
            id: slideAnimation
            duration: root.active ? Motion.enter : Motion.exit
            easing.type: Easing.InOutCubic
        }
    }
    visible: presented && !GlobalStates.lockscreenVisible
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rebos_shell-anime"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region {
        Region { item: card; radius: card.radius }
        // Keep the mask nonempty when the sheet is fully off screen.
        Region { x: -2; y: -2; width: 1; height: 1 }
    }

    function toggle(): void {
        if (opened) { opened = false; return; }
        screenName = NiriService.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        Visibilities.setActiveModule("");
        opened = true;
        backendStarted = true;
        if (ready && shows.count === 0 && !loading) load(false);
        Qt.callLater(() => pageView === "browse" ? search.focusInput() : card.forceActiveFocus());
    }
    function back(): void {
        if (pageView === "settings") pageView = previousPage;
        else if (pageView === "filters") pageView = "browse";
        else if (pageView === "details") pageView = "browse";
        else opened = false;
        if (pageView === "browse" && opened) Qt.callLater(() => search.focusInput());
    }
    function send(data): void {
        if (ready) backend.write(JSON.stringify(data) + "\n");
    }
    function switchMedia(kind: string): void {
        if (mediaKind === kind) return;
        const items = [];
        for (let i = 0; i < shows.count; i++) items.push(Object.assign({}, shows.get(i)));
        tabStates[mediaKind] = {items: items, query: query, category: category, filters: appliedFilters,
            page: cataloguePage, hasMore: hasMore, message: message, scroll: grid.contentY,
            needsLoad: loading || loadFailed, pendingAppend: loading && cataloguePage > 1};
        requestId++;
        detailRequest++;
        mediaKind = kind;
        pageView = "browse";
        loading = false;
        detailLoading = false;
        loadFailed = false;
        details = ({});
        episodes = [];
        selectedShow = ({});
        const state = tabStates[kind];
        query = state?.query ?? "";
        search.text = query;
        category = state?.category ?? "most-popular";
        appliedFilters = state?.filters ?? ({});
        draftFilters = Object.assign({}, appliedFilters);
        cataloguePage = state?.page ?? 1;
        hasMore = state?.hasMore ?? true;
        shows.clear();
        if (state) {
            for (const item of state.items) shows.append(item);
            message = state.message;
            if (state.needsLoad && !state.items.length) load(false);
            else {
                if (state.pendingAppend) cataloguePage--;
                if (state.needsLoad) load(true);
                Qt.callLater(() => { grid.contentY = state.scroll; });
            }
        } else load(false);
        categoryPicker.currentIndex = Math.max(0, (mediaKind === "anime" ? ["most-popular", "recently-updated", "top-rated", "history"] : mediaKind === "youtube" ? ["most-popular", "history"] : ["most-popular", "featured", "recently-updated", "history"]).indexOf(category));
        Qt.callLater(() => search.focusInput());
    }
    function chooseRecommendation(value: string): void {
        category = value;
        query = "";
        search.text = "";
        categoryPicker.currentIndex = 0;
        load(false);
    }
    function browseCredit(prefix: string, value: string): void {
        pageView = "browse";
        query = prefix + ": " + value;
        search.text = query;
        load(false);
        Qt.callLater(() => search.focusInput());
    }
    function episodeLabel(value: string): string {
        return details.episodeLabels?.[value] ?? (mediaKind === "movies" ? "Movie" : mediaKind === "youtube" ? "Video" : "Episode " + value);
    }
    function chooseSeason(index: int): void {
        const season = details.seasons?.[index];
        if (!season || season.id === details.seasonId) return;
        detailRequest++;
        detailLoading = true;
        episodes = [];
        send({action: "season", request: detailRequest, show: selectedShow, seasonId: season.id});
    }
    function load(append: bool): void {
        if (!ready || (append && (loading || !hasMore))) return;
        requestId++;
        if (!append) { cataloguePage = 1; shows.clear(); hasMore = true; }
        else cataloguePage++;
        loading = true;
        loadFailed = false;
        message = "Loading " + mediaName.toLowerCase() + "…";
        send({action: "catalogue", request: requestId, kind: mediaKind, category: category, query: query, page: cataloguePage, filters: appliedFilters});
    }
    function openFilters(): void {
        if (mediaKind !== "anime") return;
        draftFilters = Object.assign({}, appliedFilters);
        pageView = "filters";
        card.forceActiveFocus();
    }
    function setDraftFilter(key: string, value: string): void {
        const updated = Object.assign({}, draftFilters);
        updated[key] = value;
        draftFilters = updated;
    }
    function applyFilters(): void {
        if (draftFilters.sy && draftFilters.ey && Number(draftFilters.sy) > Number(draftFilters.ey)) return;
        appliedFilters = Object.assign({}, draftFilters);
        if (category === "history") { category = "most-popular"; categoryPicker.currentIndex = 0; }
        query = search.text.trim();
        pageView = "browse";
        load(false);
        Qt.callLater(() => search.focusInput());
    }
    function loadNearBottom(): void {
        const ahead = mediaKind === "movies" || mediaKind === "tv" ? grid.height * 2 : unit * 12;
        if (pageView === "browse" && !loadFailed && grid.contentY > 0 && grid.contentY + grid.height >= grid.contentHeight - ahead) load(true);
    }
    function selectShow(show): void {
        selectedShow = Object.assign({}, show, {kind: mediaKind});
        details = ({});
        episodes = [];
        selectedEpisode = 0;
        pageView = "details";
        detailLoading = true;
        detailRequest++;
        send({action: "details", request: detailRequest, show: selectedShow});
        Qt.callLater(() => { if (detailScroll.contentItem) detailScroll.contentItem.contentY = 0; });
        card.forceActiveFocus();
    }
    function playCard(index: int): void {
        if (!ready || index < 0 || index >= shows.count) return;
        grid.currentIndex = index;
        send({action: "quick_play", show: Object.assign({}, shows.get(index), {kind: mediaKind})});
    }
    function updateSetting(key: string, value): void {
        const updated = Object.assign({}, settings);
        updated[key] = value;
        settings = updated;
        send({action: "settings", settings: updated});
    }
    function receive(line: string): void {
        let data;
        try { data = JSON.parse(line); } catch (_) { message = "Could not read the media service response"; return; }
        Qt.callLater(() => {
            if (data.event === "ready") {
                ready = true;
                settings = data.settings;
                torbox = data.torbox ?? ({connected: false, text: "TorBox is not connected."});
                torboxBusy = false;
                filterOptions = data.filterOptions ?? [];
                mediaGenres = data.mediaGenres ?? [];
                youtubeRecommendations = data.youtubeRecommendations ?? [];
                if (shows.count === 0) load(false);
            } else if (data.event === "catalogue" && data.request === requestId) {
                const existing = new Set();
                for (let i = 0; i < shows.count; i++) existing.add(shows.get(i).id);
                let added = 0;
                const items = Array.isArray(data.data) ? data.data : (data.data.items ?? []);
                for (const show of items) {
                    if (!existing.has(show.id)) { shows.append(Object.assign({kind: "anime", url: "", route: "", availabilityLabel: "Availability not confirmed", sourceAvailability: "unknown"}, show)); existing.add(show.id); added++; }
                }
                hasMore = !Array.isArray(data.data) ? data.data.hasMore : added > 0 && (category !== "history" || query.length > 0 || filterCount > 0);
                loading = false;
                const countMessage = (isYoutube && !query && category !== "history" ? (youtubeRecommendations.find(row => row.id === category)?.title ?? "Popular") + " recommendations · " : filterCount > 0 ? "Filtered · " : "") + shows.count + (hasMore ? " results · Scroll for more" : " results · End of results");
                message = (mediaKind === "movies" || mediaKind === "tv" ? "English audio · No CAM · HTTPS only · " : "") + countMessage;
                if (grid.currentIndex < 0 && shows.count) grid.currentIndex = 0;
            } else if (data.event === "availability") {
                for (const show of data.data) {
                    for (let i = 0; i < shows.count; i++) {
                        if (shows.get(i).id === show.id) {
                            shows.setProperty(i, "availabilityLabel", show.availabilityLabel);
                            shows.setProperty(i, "sourceAvailability", show.sourceAvailability);
                            break;
                        }
                    }
                    for (const kind of ["movies", "tv"]) {
                        const state = tabStates[kind];
                        if (state) for (const item of state.items) {
                            if (item.id === show.id) Object.assign(item, {availabilityLabel: show.availabilityLabel, sourceAvailability: show.sourceAvailability});
                        }
                    }
                    if (selectedShow.id === show.id) selectedShow = Object.assign({}, selectedShow, {availabilityLabel: show.availabilityLabel, sourceAvailability: show.sourceAvailability});
                }
            } else if (data.event === "details" && data.request === detailRequest) {
                details = data.data;
                selectedShow = Object.assign({}, selectedShow, data.data.show ?? ({}), {episodeLabels: data.data.episodeLabels ?? ({})});
                episodes = data.data.episodes;
                selectedEpisode = data.data.resumeIndex;
                detailLoading = false;
                if (pageView === "details") Qt.callLater(() => mediaKind === "movies" || (isYoutube && episodes.length <= 1) ? playSelection.forceActiveFocus() : episodeGrid.forceActiveFocus());
            } else if (data.event === "season" && data.request === detailRequest) {
                details = Object.assign({}, details, data.data);
                selectedShow = Object.assign({}, selectedShow, data.data.show ?? ({}), {episodeLabels: data.data.episodeLabels ?? ({})});
                episodes = data.data.episodes;
                selectedEpisode = data.data.resumeIndex;
                detailLoading = false;
            } else if (["torbox", "torbox_connect", "torbox_check", "torbox_disconnect", "torbox_key"].indexOf(data.event) >= 0) {
                torbox = data.data;
                torboxBusy = false;
                if (data.event === "torbox_connect" && torbox.url) {
                    Qt.openUrlExternally(torbox.url);
                    opened = false;
                }
            } else if (data.event === "settings") {
                settings = data.data;
            } else if (data.event === "verification") {
                opened = false;
                playback = data.text;
            } else if (data.event === "playback") {
                playback = data.text;
            } else if (data.event === "paused") {
                playbackPaused = data.value;
            } else if (data.event === "captions") {
                captionStatus = data.text;
            } else if (data.event === "subtitle-state") {
                subtitlesOff = data.off;
                whisperSelected = data.whisper ?? !data.off;
            } else if (data.event === "episode" && data.show === selectedShow.id) {
                selectedEpisode = data.index;
            } else if (data.event === "poster") {
                for (let i = 0; i < shows.count; i++) {
                    if (shows.get(i).id === data.data.id) shows.setProperty(i, "image", data.data.image);
                }
                if (selectedShow.id === data.data.id) selectedShow = Object.assign({}, selectedShow, {image: data.data.image});
            } else if (data.event === "error") {
                if (data.action === "catalogue" && data.request === requestId) {
                    loading = false; loadFailed = true;
                    if (cataloguePage > 1) cataloguePage--;
                    message = data.text;
                } else if ((data.action === "details" || data.action === "season") && data.request === detailRequest) {
                    detailLoading = false; details = Object.assign({}, details, {warning: data.text});
                } else if ((data.action ?? "").startsWith("torbox_")) {
                    torboxBusy = false;
                    torbox = Object.assign({}, torbox, {text: data.text});
                } else if (data.action !== "catalogue" && data.action !== "details" && data.action !== "season" && data.action !== "poster") playback = data.text;
            }
        });
    }

    IpcHandler {
        target: "anime"
        function toggle(): void { root.toggle(); }
        function close(): void { root.opened = false; }
        function back(): void { root.back(); }
        function select(index: int): void {
            if (index >= 0 && index < shows.count) root.selectShow(shows.get(index));
        }
        function quickPlay(index: int): void { root.playCard(index); }
        function scrollToEnd(): void { grid.positionViewAtEnd(); root.loadNearBottom(); }
        function media(kind: string): void { if (["anime", "movies", "tv", "youtube"].indexOf(kind) >= 0) root.switchMedia(kind); }
        function searchQuery(value: string): void { search.text = value; root.query = value.trim(); root.load(false); }
        function recommendation(value: string): void {
            if (root.isYoutube && root.youtubeRecommendations.some(row => row.id === value)) root.chooseRecommendation(value);
        }
        function season(index: int): void { root.chooseSeason(index); }
        function play(index: int): void {
            if (index >= 0 && index < root.episodes.length) root.send({action: "play", show: root.selectedShow, episodes: root.episodes, index: index});
        }
        function filters(): void { root.openFilters(); }
        function filter(key: string, value: string): void { root.setDraftFilter(key, value); }
        function applyFilters(): void { root.applyFilters(); }
        function settings(): void { root.previousPage = root.pageView; root.pageView = "settings"; card.forceActiveFocus(); }
        function status(): string {
            return JSON.stringify({open: root.opened, presented: root.presented, slideProgress: root.slideProgress,
                sheetY: card.y, sheetHeight: card.height, screenHeight: root.height,
                ready: root.ready, view: root.pageView,
                searchText: search.text, searchFocused: search.inputActiveFocus, cardFocused: card.activeFocus, kind: root.mediaKind, category: root.category, hasMore: root.hasMore, title: root.selectedShow.title ?? "", seasonCount: root.details.seasons?.length ?? 0, shows: shows.count, loading: root.loading, detailLoading: root.detailLoading,
                cast: root.details.cast ?? [], directors: root.details.directors ?? [], genres: root.details.genres ?? [], recommendationGroups: root.youtubeRecommendations.length, episodes: root.episodes.length, metadata: root.details.metadata?.length ?? 0,
                descriptionLength: root.details.description?.length ?? 0, filters: root.appliedFilters,
                filterFields: root.filterOptions.length, page: root.cataloguePage, message: root.message,
                liveSubtitles: root.settings.live_subtitles ?? true, captions: root.captionStatus,
                captionDelay: root.settings.caption_delay ?? 0, subtitlesOff: root.subtitlesOff, captionsEnabled: root.captionsEnabled});
        }
    }
    Process {
        id: backend
        command: ["python", "-u", Quickshell.env("HOME") + "/code/anime-streamer/menu_client.py"]
        stdinEnabled: true
        running: root.backendStarted
        stdout: SplitParser { onRead: line => root.receive(line) }
        stderr: StdioCollector { onStreamFinished: { if (text.length) console.warn("Anime backend:", text); } }
        onExited: {
            root.ready = false;
            root.backendStarted = false;
            root.loading = false;
            root.detailLoading = false;
            root.message = "Playback menu disconnected. Close and reopen it to reconnect.";
        }
    }
    ListModel { id: shows }

    component MenuButton: Button {
        id: control
        property bool selected: false
        property bool glowing: false
        padding: root.unit * 0.75
        hoverEnabled: true
        opacity: enabled ? 1 : 0.45
        Keys.onReturnPressed: event => { if (enabled) clicked(); event.accepted = true; }
        Keys.onEnterPressed: event => { if (enabled) clicked(); event.accepted = true; }
        contentItem: StyledText {
            text: control.text
            color: control.selected ? Colors.overPrimary : Colors.overSurface
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: StyledRect {
            variant: control.selected ? "primary" : control.hovered || control.activeFocus ? "focus" : "common"
            radius: Styling.radius(8)
            layer.enabled: control.glowing
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Colors.primary
                shadowBlur: 0.65
                shadowOpacity: 0.65
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }
        }
    }
    component MenuCombo: SettingsComboBox {}

    MouseArea { anchors.fill: parent; onClicked: root.opened = false }
    StyledRect {
        id: card
        variant: "popup"
        radius: Styling.radius(20)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width - root.unit * 2, root.unit * 90)
        height: Math.min(root.height - root.unit * 4, root.unit * 53)
        y: root.height - (height + root.unit) * root.slideProgress
        clip: true
        focus: true
        Keys.onEscapePressed: event => { root.back(); event.accepted = true; }
        MouseArea { anchors.fill: parent; onClicked: card.forceActiveFocus() }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.unit * 1.5
            spacing: root.unit
            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.unit * 3
                Layout.preferredHeight: root.unit * 0.25
                variant: "focus"
                radius: height / 2
            }
            RowLayout {
                Layout.fillWidth: true
                MenuButton { visible: root.pageView !== "browse"; text: "‹ Back"; onClicked: root.back() }
                StyledText {
                    Layout.fillWidth: true
                    text: root.pageView === "details" ? (root.selectedShow.title ?? root.mediaName) : root.pageView === "settings" ? "Playback settings" : root.pageView === "filters" ? "Search filters" : "Media Browser"
                    font.pixelSize: Styling.fontSize(6)
                    font.bold: true
                    elide: Text.ElideRight
                }
                BusyIndicator { running: root.loading || root.detailLoading; visible: running; implicitWidth: root.unit * 2; implicitHeight: implicitWidth }
                MenuButton {
                    text: "Settings"
                    visible: root.pageView !== "settings"
                    onClicked: { root.previousPage = root.pageView; root.pageView = "settings"; }
                }
                MenuButton { text: "×"; Accessible.name: "Close media menu"; onClicked: root.opened = false }
            }
            RowLayout {
                visible: root.pageView === "browse"
                Layout.fillWidth: true
                Repeater {
                    model: [{kind: "anime", title: "Anime"}, {kind: "movies", title: "Movies"}, {kind: "tv", title: "TV"}, {kind: "youtube", title: "YouTube"}]
                    delegate: MenuButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: modelData.title
                        selected: root.mediaKind === modelData.kind
                        onClicked: root.switchMedia(modelData.kind)
                    }
                }
            }
            ColumnLayout {
                visible: root.pageView === "browse"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.unit
                RowLayout {
                    Layout.fillWidth: true
                    SearchInput {
                        id: search
                        Layout.fillWidth: true
                        placeholderText: root.isYoutube ? "Search YouTube or paste a link…" : "Search " + root.mediaName.toLowerCase() + "…"
                        clearOnEscape: false
                        onAccepted: { root.query = text.trim(); root.load(false); }
                        onEscapePressed: root.back()
                        onDownPressed: { grid.forceActiveFocus(); if (grid.currentIndex < 0 && shows.count) grid.currentIndex = 0; }
                    }
                    MenuCombo {
                        visible: root.mediaKind === "movies" || root.mediaKind === "tv"
                        model: ["Title", "Actor", "Genre"]
                        currentIndex: search.text.toLowerCase().startsWith("actor:") ? 1 : search.text.toLowerCase().startsWith("genre:") ? 2 : 0
                        onActivated: {
                            const value = search.text.replace(/^(actor|genre|title):\s*/i, "");
                            search.text = ["", "actor: ", "genre: "][currentIndex] + value;
                            search.focusInput();
                        }
                    }
                    MenuCombo {
                        visible: (root.mediaKind === "movies" || root.mediaKind === "tv") && search.text.toLowerCase().startsWith("genre:")
                        Layout.preferredWidth: root.unit * 13
                        model: ["Choose genre"].concat(Array.from(root.mediaGenres))
                        currentIndex: Math.max(0, root.mediaGenres.findIndex(genre => genre.toLowerCase() === search.text.replace(/^genre:\s*/i, "").trim().toLowerCase()) + 1)
                        enabled: root.ready && root.mediaGenres.length > 0
                        Accessible.name: "Movie or TV genre"
                        popup.height: Math.min(popup.implicitHeight, card.height * 0.55)
                        onActivated: {
                            if (currentIndex === 0) return;
                            search.text = "genre: " + currentText;
                            root.query = search.text;
                            root.load(false);
                            search.focusInput();
                        }
                    }
                    MenuButton { text: "Search"; onClicked: { root.query = search.text.trim(); root.load(false); } }
                    MenuButton { visible: root.mediaKind === "anime"; text: root.filterCount > 0 ? "Filters (" + root.filterCount + ")" : "Filters"; selected: root.filterCount > 0; enabled: root.ready; onClicked: root.openFilters() }
                    MenuCombo {
                        id: categoryPicker
                        model: root.mediaKind === "anime" ? ["Popular", "Recently updated", "Top rated", "History"] : root.isYoutube ? ["Recommended", "History"] : ["Popular", "Featured", "New releases", "History"]
                        onActivated: { root.category = (root.mediaKind === "anime" ? ["most-popular", "recently-updated", "top-rated", "history"] : root.isYoutube ? ["most-popular", "history"] : ["most-popular", "featured", "recently-updated", "history"])[currentIndex]; search.text = ""; root.query = ""; root.appliedFilters = ({}); root.draftFilters = ({}); root.load(false); }
                    }
                }
                StyledText {
                    visible: root.mediaKind === "movies" || root.mediaKind === "tv"
                    Layout.fillWidth: true
                    text: search.text.toLowerCase().startsWith("actor:")
                        ? "Search catalogue cast, e.g. actor: Anne Hathaway. Load more checks further titles; cast coverage may be incomplete."
                        : "Search a title, actor: Anne Hathaway, or genre: Comedy. Genres include Action, Drama, Horror, Romance and Sci-Fi."
                    color: Colors.overSurfaceVariant
                    wrapMode: Text.Wrap
                }
                GridLayout {
                    visible: root.isYoutube
                    Layout.fillWidth: true
                    columns: width < root.unit * 55 ? 4 : 8
                    columnSpacing: root.unit * 0.5
                    rowSpacing: root.unit * 0.5
                    Repeater {
                        model: root.youtubeRecommendations
                        delegate: MenuButton {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            text: modelData.title
                            selected: !root.query && root.category === modelData.id
                            enabled: root.ready
                            onClicked: root.chooseRecommendation(modelData.id)
                        }
                    }
                }
                StyledText {
                    visible: root.isYoutube && !root.query && root.category !== "history"
                    Layout.fillWidth: true
                    text: (root.youtubeRecommendations.find(row => row.id === root.category)?.title ?? "Popular") + " recommendations · Public search suggestions, without sign-in or personalization. Search or paste a link for something specific."
                    color: Colors.overSurfaceVariant
                    wrapMode: Text.Wrap
                }
                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: shows
                    cellWidth: width / Math.max(1, Math.floor(width / (root.unit * (root.isYoutube ? 22 : 13))))
                    cellHeight: root.isYoutube ? cellWidth * 0.5625 + root.unit * 6 : cellWidth * 1.55
                    keyNavigationEnabled: true
                    onContentYChanged: root.loadNearBottom()
                    onMovementEnded: root.loadNearBottom()
                    Keys.onReturnPressed: { if (currentIndex >= 0) root.selectShow(shows.get(currentIndex)); }
                    Keys.onEnterPressed: { if (currentIndex >= 0) root.selectShow(shows.get(currentIndex)); }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_P && event.modifiers === Qt.NoModifier) {
                            root.playCard(currentIndex);
                            event.accepted = true;
                        }
                    }
                    Keys.onEscapePressed: root.back()
                    ScrollBar.vertical: ScrollBar {}
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width * 0.8
                        visible: shows.count === 0 && !root.loading
                        spacing: root.unit
                        StyledText {
                            Layout.fillWidth: true
                            text: "No results"
                            font.pixelSize: Styling.fontSize(4)
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.message
                            color: Colors.overSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                        }
                    }
                    delegate: Item {
                        id: poster
                        required property int index
                        required property string title
                        required property string image
                        required property string description
                        required property string availabilityLabel
                        width: grid.cellWidth
                        height: grid.cellHeight
                        StyledRect {
                            anchors.fill: parent
                            anchors.margins: root.unit * 0.4
                            variant: grid.currentIndex === poster.index ? "focus" : "common"
                            radius: Styling.radius(12)
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: root.unit * 0.5
                                spacing: root.unit * 0.5
                                Image {
                                    source: poster.image
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredHeight: root.isYoutube ? width * 0.5625 : -1
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: root.unit * (root.isYoutube ? 32 : 18)
                                    clip: true
                                    onStatusChanged: {
                                        if (status === Image.Error && source.toString().startsWith("https://")) root.send({action: "poster", id: shows.get(poster.index).id, url: source.toString()});
                                    }
                                }
                                StyledText {
                                    text: poster.title
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.unit * 2.8
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    visible: root.mediaKind === "movies" || root.mediaKind === "tv"
                                    text: poster.availabilityLabel
                                    Layout.fillWidth: true
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                    color: Colors.overSurfaceVariant
                                }
                                StyledText {
                                    visible: root.isYoutube
                                    text: poster.description
                                    Layout.fillWidth: true
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: Colors.overSurfaceVariant
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: { if (containsMouse) grid.currentIndex = poster.index; }
                                onClicked: { grid.currentIndex = poster.index; root.selectShow(shows.get(poster.index)); }
                            }
                            MenuButton {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: root.unit * 0.65
                                text: "▶ Play"
                                selected: true
                                enabled: root.ready
                                Accessible.name: "Play or resume " + poster.title
                                ToolTip.visible: hovered
                                ToolTip.text: "Play or resume directly · P on a selected card"
                                onClicked: root.playCard(poster.index)
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: root.message; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                    MenuButton { text: "Load more"; visible: root.hasMore && !root.loading && !root.loadFailed; onClicked: root.load(true) }
                    MenuButton { text: "Retry"; visible: root.loadFailed; onClicked: root.load(shows.count > 0) }
                }
            }
            ColumnLayout {
                visible: root.pageView === "details"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.unit
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: root.mediaKind === "movies" || (root.isYoutube && root.episodes.length <= 1)
                    Layout.preferredHeight: card.height * 0.43
                    Layout.maximumHeight: card.height * (root.mediaKind === "movies" ? 0.78 : root.isYoutube && root.episodes.length <= 1 ? 0.7 : 0.48)
                    Layout.minimumHeight: 0
                    spacing: root.unit * 1.5
                    Image {
                        source: root.selectedShow.image ?? ""
                        Layout.preferredWidth: root.unit * (root.isYoutube ? 26 : 14)
                        Layout.maximumWidth: card.width * 0.42
                        Layout.fillHeight: true
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        onStatusChanged: {
                            if (status === Image.Error && source.toString().startsWith("https://")) root.send({action: "poster", id: root.selectedShow.id, url: source.toString()});
                        }
                    }
                    ScrollView {
                        id: detailScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        clip: true
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: parent.width
                            spacing: root.unit
                            StyledText {
                                text: root.details.title || root.selectedShow.title || ""
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Styling.fontSize(5)
                                font.bold: true
                            }
                            StyledText {
                                visible: root.mediaKind === "movies" || root.mediaKind === "tv"
                                text: [root.details.year, root.details.runtime, root.details.rating ? "IMDb " + root.details.rating + " / 10" : ""].filter(Boolean).join(" · ")
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Colors.primary
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: root.unit * 0.5
                                visible: (root.details.genres?.length ?? 0) > 0
                                Repeater {
                                    model: root.details.genres ?? []
                                    delegate: MenuButton {
                                        required property string modelData
                                        text: modelData
                                        width: Math.min(implicitWidth, parent.width)
                                        Accessible.name: "Browse " + modelData + " titles"
                                        onClicked: root.browseCredit("genre", modelData)
                                    }
                                }
                            }
                            StyledText { text: root.isYoutube ? "Description" : "Overview"; font.bold: true }
                            StyledText {
                                text: root.details.description || root.selectedShow.description || (root.detailLoading ? "Loading information…" : "No description available")
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                            StyledText { visible: (root.details.cast?.length ?? 0) > 0; text: "Cast · select an actor to explore"; font.bold: true }
                            Flow {
                                Layout.fillWidth: true
                                spacing: root.unit * 0.5
                                visible: (root.details.cast?.length ?? 0) > 0
                                Repeater {
                                    model: root.details.cast ?? []
                                    delegate: MenuButton {
                                        required property string modelData
                                        text: modelData
                                        width: Math.min(implicitWidth, parent.width)
                                        Accessible.name: "Find titles with " + modelData
                                        onClicked: root.browseCredit("actor", modelData)
                                    }
                                }
                            }
                            StyledText {
                                visible: (root.details.directors?.length ?? 0) > 0
                                text: "Directed by " + (root.details.directors ?? []).join(", ")
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                            StyledText {
                                visible: !!root.details.country || !!root.details.released
                                text: [root.details.country, root.details.released ? "Released " + root.details.released : ""].filter(Boolean).join(" · ")
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Colors.overSurfaceVariant
                            }
                            StyledText { visible: root.mediaKind !== "movies" && root.mediaKind !== "tv"; text: (root.details.metadata ?? []).join("\n"); Layout.fillWidth: true; wrapMode: Text.Wrap; color: Colors.overSurfaceVariant }
                            StyledText { visible: root.mediaKind === "movies" || root.mediaKind === "tv"; text: (root.selectedShow.availabilityLabel || "Availability not confirmed") + "\nCache checks do not verify playback. TV labels check the first episode; other episodes may differ."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Colors.overSurfaceVariant }
                        }
                    }
                }
                StyledText { visible: text.length > 0; text: root.details.warning ?? ""; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Colors.overSurfaceVariant }
                RowLayout {
                    Layout.fillWidth: true
                    MenuCombo {
                        visible: root.mediaKind === "tv" && (root.details.seasons?.length ?? 0) > 0
                        enabled: !root.detailLoading
                        model: (root.details.seasons ?? []).map(season => season.title)
                        currentIndex: Math.max(0, (root.details.seasons ?? []).findIndex(season => season.id === root.details.seasonId))
                        onActivated: root.chooseSeason(currentIndex)
                    }
                    StyledText { text: root.episodes.length + (root.isYoutube ? (root.episodes.length === 1 ? " video" : " videos") : root.mediaKind === "movies" ? " movie" : (root.episodes.length === 1 ? " episode" : " episodes")); Layout.fillWidth: true; font.bold: true }
                    MenuButton {
                        id: playSelection
                        text: root.episodes.length ? (root.mediaKind === "movies" || root.isYoutube ? "Play" : "Play · " + root.episodeLabel(root.episodes[root.selectedEpisode])) : root.detailLoading ? "Loading…" : "Unavailable"
                        enabled: root.episodes.length > 0
                        selected: true
                        onClicked: root.send({action: "play", show: root.selectedShow, episodes: root.episodes, index: root.selectedEpisode})
                    }
                }
                GridView {
                    id: episodeGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: root.mediaKind === "movies" ? 0 : root.unit * 7
                    visible: root.mediaKind !== "movies" && (!root.isYoutube || root.episodes.length > 1)
                    clip: true
                    model: root.episodes
                    keyNavigationEnabled: true
                    currentIndex: root.selectedEpisode
                    onCurrentIndexChanged: { if (currentIndex >= 0) root.selectedEpisode = currentIndex; }
                    Keys.onReturnPressed: { if (root.episodes.length) root.send({action: "play", show: root.selectedShow, episodes: root.episodes, index: root.selectedEpisode}); }
                    Keys.onEscapePressed: root.back()
                    cellWidth: width / Math.max(1, Math.floor(width / (root.unit * (root.mediaKind === "anime" ? 7 : 26))))
                    cellHeight: root.unit * 3.5
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Item {
                        id: episode
                        required property int index
                        required property string modelData
                        width: episodeGrid.cellWidth
                        height: episodeGrid.cellHeight
                        MenuButton {
                            anchors.fill: parent
                            anchors.margins: root.unit * 0.25
                            text: root.mediaKind === "anime" ? "Ep " + episode.modelData : root.episodeLabel(episode.modelData)
                            selected: root.selectedEpisode === episode.index
                            onClicked: root.selectedEpisode = episode.index
                            onDoubleClicked: root.send({action: "play", show: root.selectedShow, episodes: root.episodes, index: episode.index})
                        }
                    }
                }
            }
            ColumnLayout {
                visible: root.pageView === "filters"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.unit * 1.2
                StyledText {
                    Layout.fillWidth: true
                    text: "Combine filters with your search, or leave the search empty to browse matching shows."
                    wrapMode: Text.Wrap
                    color: Colors.overSurfaceVariant
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    GridLayout {
                        width: parent.width
                        columns: width < root.unit * 48 ? 2 : 3
                        columnSpacing: root.unit * 1.5
                        rowSpacing: root.unit * 1.5
                        Repeater {
                            model: root.filterOptions
                            delegate: ColumnLayout {
                                id: filterField
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: root.unit * 0.5
                                StyledText { text: filterField.modelData.label; font.bold: true }
                                MenuCombo {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    model: filterField.modelData.options
                                    textRole: "label"
                                    valueRole: "value"
                                    currentIndex: Math.max(0, filterField.modelData.options.findIndex(option => option.value === (root.draftFilters[filterField.modelData.key] ?? "")))
                                    onActivated: root.setDraftFilter(filterField.modelData.key, currentValue)
                                    Accessible.name: filterField.modelData.label
                                    popup.height: Math.min(popup.implicitHeight, card.height * 0.55)
                                }
                            }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "From year and To year set the release-date range. Language filters source availability; playback audio is chosen in Settings. Browse categories clear the active filters."
                    wrapMode: Text.Wrap
                    color: Colors.overSurfaceVariant
                }
                StyledText {
                    visible: Boolean(root.draftFilters.sy && root.draftFilters.ey && Number(root.draftFilters.sy) > Number(root.draftFilters.ey))
                    text: "From year must be earlier than or equal to To year."
                    color: Colors.error
                }
                RowLayout {
                    Layout.fillWidth: true
                    MenuButton { text: "Reset filters"; onClicked: root.draftFilters = ({}) }
                    Item { Layout.fillWidth: true }
                    MenuButton {
                        text: "Apply filters"
                        selected: true
                        enabled: root.ready && !(root.draftFilters.sy && root.draftFilters.ey && Number(root.draftFilters.sy) > Number(root.draftFilters.ey))
                        onClicked: root.applyFilters()
                    }
                }
            }
            ScrollView {
                visible: root.pageView === "settings"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width
                    spacing: root.unit * 1.2
                    StyledText { text: "TorBox"; font.bold: true }
                    StyledText {
                        text: root.torbox.text ?? "TorBox is not connected."
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Colors.overSurfaceVariant
                    }
                    StyledText {
                        visible: !!root.torbox.code && !root.torbox.connected
                        text: "Sign-in code: " + (root.torbox.code ?? "")
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        MenuButton {
                            text: root.torboxBusy ? "Connecting…" : "Connect TorBox"
                            enabled: root.ready && !root.torboxBusy
                            onClicked: { root.torboxBusy = true; root.send({action: "torbox_connect"}); }
                        }
                        MenuButton {
                            text: "Check connection"
                            enabled: root.ready && !root.torboxBusy
                            onClicked: { root.torboxBusy = true; root.send({action: "torbox_check"}); }
                        }
                        MenuButton {
                            text: root.torbox.connected ? "Disconnect" : "Cancel sign-in"
                            enabled: root.ready
                            onClicked: { torboxKey.text = ""; root.send({action: "torbox_disconnect"}); }
                        }
                    }
                    StyledText {
                        text: "Create a TorBox account and activate the 24-hour Pro demo if offered, then press Connect. Approve Media Browser on TorBox. Only cached files are used; your computer streams HTTPS and does not run torrents."
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Colors.overSurfaceVariant
                    }
                    RowLayout {
                        MenuButton { text: "Open TorBox"; onClicked: { Qt.openUrlExternally("https://torbox.app"); root.opened = false; } }
                        MenuButton { text: root.torboxManual ? "Hide API key entry" : "Use API key instead"; onClicked: { root.torboxManual = !root.torboxManual; torboxKey.text = ""; } }
                    }
                    RowLayout {
                        visible: root.torboxManual
                        Layout.fillWidth: true
                        TextField {
                            id: torboxKey
                            Layout.fillWidth: true
                            placeholderText: "TorBox API key"
                            echoMode: TextInput.Password
                            color: Colors.overSurface
                            placeholderTextColor: Colors.overSurfaceVariant
                            Accessible.name: "TorBox API key"
                            background: Rectangle { color: Colors.surface; radius: root.unit * 0.6; border.color: Colors.overSurfaceVariant }
                        }
                        MenuButton {
                            text: "Connect key"
                            enabled: root.ready && !root.torboxBusy && torboxKey.text.trim().length > 0
                            onClicked: { root.torboxBusy = true; root.send({action: "torbox_key", key: torboxKey.text.trim()}); torboxKey.text = ""; }
                        }
                    }
                    StyledText {
                        text: root.torbox.connected ? "Movies and TV use cached TorBox files over HTTPS. Local torrents and browser verification are disabled. Playback checks English audio, video duration and seeking before opening the player." : "Movies and TV use direct HTTPS streams. Local torrents and browser verification are disabled. Free sources may be unavailable; playback checks English audio, video duration and seeking before opening the player."
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Colors.overSurfaceVariant
                    }
                    CheckBox {
                        text: "Load the next episode paused"
                        palette.windowText: Colors.overSurface
                        checked: root.settings.auto_next ?? true
                        onToggled: root.updateSetting("auto_next", checked)
                    }
                    CheckBox {
                        text: "Generate live English subtitles locally"
                        palette.windowText: Colors.overSurface
                        checked: root.settings.live_subtitles ?? true
                        onToggled: root.updateSetting("live_subtitles", checked)
                    }
                    StyledText {
                        text: "Whisper captions use speech detection and short, word-timed phrases to follow the dialogue. Use English audio; choose Dub for anime. Look for Live English · local Whisper in VLC’s Subtitle → Sub Track menu. YouTube uses its own captions. Switching to provided subtitles keeps your selection."
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Colors.overSurfaceVariant
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { text: "Whisper timing"; Layout.preferredWidth: root.unit * 10 }
                        Slider {
                            Layout.fillWidth: true
                            from: -10; to: 10; stepSize: 0.1
                            value: root.settings.caption_delay ?? 0
                            onMoved: root.updateSetting("caption_delay", Math.round(value * 10) / 10)
                            Accessible.name: "Whisper subtitle delay in seconds"
                        }
                        StyledText { text: Number(root.settings.caption_delay ?? 0).toFixed(1) + " s" }
                        MenuButton { text: "Reset"; onClicked: root.updateSetting("caption_delay", 0) }
                    }
                    StyledText {
                        text: "Move right to show Whisper captions later; left shows them earlier. Changes apply immediately and save automatically. Provided subtitles are unaffected."
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Colors.overSurfaceVariant
                    }
                    CheckBox {
                        text: "Start videos fullscreen"
                        palette.windowText: Colors.overSurface
                        checked: root.settings.fullscreen ?? false
                        onToggled: root.updateSetting("fullscreen", checked)
                    }
                    RowLayout {
                        StyledText { text: "Quality"; Layout.preferredWidth: root.unit * 10 }
                        MenuCombo { model: ["best", "1080p", "720p", "480p", "worst"]; currentIndex: Math.max(0, model.indexOf(root.settings.quality ?? "best")); onActivated: root.updateSetting("quality", currentText) }
                    }
                    RowLayout {
                        StyledText { text: "Anime audio"; Layout.preferredWidth: root.unit * 10 }
                        MenuCombo { model: ["sub", "dub"]; currentIndex: root.settings.mode === "dub" ? 1 : 0; onActivated: root.updateSetting("mode", currentText) }
                    }
                    RowLayout {
                        StyledText { text: "Starting volume"; Layout.preferredWidth: root.unit * 10 }
                        Slider { from: 0; to: 100; stepSize: 5; value: root.settings.volume ?? 80; onMoved: root.updateSetting("volume", Math.round(value)) }
                        StyledText { text: (root.settings.volume ?? 80) + "%" }
                    }
                    StyledText { text: "When an episode ends, load the next one in the same player and pause it. Press Play here or Space in VLC when you are ready. Turning this off stops at the end of the current episode. Settings save automatically."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Colors.overSurfaceVariant }
                }
            }
            StyledText {
                visible: root.captionStatus.length > 0
                text: root.captionStatus + (root.subtitlesOff ? " · Subtitles are off in the player" : "")
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Colors.overSurfaceVariant
            }
            RowLayout {
                visible: root.playback.length > 0
                Layout.fillWidth: true
                StyledText { text: root.playback; Layout.fillWidth: true; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight }
                MenuButton { text: "Play"; visible: root.playbackPaused; selected: true; onClicked: root.send({action: "resume"}) }
                MenuButton {
                    text: "Captions"
                    visible: root.mediaKind !== "youtube"
                    checkable: true
                    checked: root.captionsEnabled
                    selected: root.captionsEnabled
                    glowing: root.captionsEnabled
                    Accessible.name: "Whisper captions in VLC"
                    onClicked: {
                        const enable = !root.captionsEnabled;
                        root.updateSetting("live_subtitles", enable);
                        if (enable) root.send({action: "show_captions"});
                    }
                }
                MenuButton { text: "Stop"; onClicked: root.send({action: "stop"}) }
            }
        }
    }
}
