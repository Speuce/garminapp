import Toybox.Lang;
import Toybox.Time;

// A small state machine shared by the button delegate and simulator tests.
// Drafts never modify saved records until the review screen is confirmed.
class AlarmController {
    enum {
        LIST, ACTIONS, HOUR, MINUTE, PERIOD, PATTERN, DAYS, INTERVAL,
        YEAR, MONTH, DAY, REVIEW, DELETE, DISCARD, TOOLS
    }
    static const PATTERNS = ["Every day", "Weekdays", "Weekends", "Custom week", "Every N days", "Once"];
    var store as AlarmStore;
    var state = LIST;
    var selection = 0;
    var cursor = 0;
    var draft as Dictionary = {};
    var notice = null;
    var command as Number = 0;
    private var _history as Array<Number> = [];
    private var _discardFrom = HOUR;

    function initialize(alarmStore as AlarmStore) { store = alarmStore; }

    function beginEdit(index) {
        if (!store.readable) { notice = store.error; return; }
        if (index >= store.records.size() && store.records.size() >= AlarmStore.MAX_ALARMS) {
            notice = "Maximum 16 alarms"; return;
        }
        draft = index < store.records.size() ? AlarmData.copy(store.records[index]) : AlarmData.create();
        _history = [];
        state = HOUR;
        cursor = 0;
        notice = null;
    }

    private function go(nextState) {
        _history.add(state);
        state = nextState;
        cursor = nextState == PATTERN ? patternIndex() : 0;
    }

    function patternIndex() {
        if (draft["repeat"] == AlarmData.INTERVAL) { return 4; }
        if (draft["repeat"] == AlarmData.ONCE) { return 5; }
        if (draft["interval"] == 1) {
            if (draft["days"] == 127) { return 0; }
            if (draft["days"] == 31) { return 1; }
            if (draft["days"] == 96) { return 2; }
        }
        return 3;
    }

    function wrap(value, low, high) {
        if (value < low) { return high; }
        if (value > high) { return low; }
        return value;
    }

    // direction is +1 for DOWN/next, -1 for UP/previous.
    function move(direction) {
        notice = null;
        if (!store.readable) { return; }
        if (state == LIST) { selection = wrap(selection + direction, 0, store.records.size()); }
        else if (state == ACTIONS) { cursor = wrap(cursor + direction, 0, 5); }
        else if (state == TOOLS) { cursor = wrap(cursor + direction, 0, 1); }
        else if (state == PATTERN) { cursor = wrap(cursor + direction, 0, PATTERNS.size() - 1); }
        else if (state == DAYS) { cursor = wrap(cursor + direction, 0, 7); }
        else if (state == DELETE || state == DISCARD) { cursor = 1 - cursor; }
        else if (state == HOUR) {
            var half = draft["hour"] >= 12 ? 12 : 0;
            draft["hour"] = wrap(draft["hour"] % 12 - direction, 0, 11) + half;
        } else if (state == MINUTE) { draft["minute"] = wrap(draft["minute"] - direction, 0, 59); }
        else if (state == PERIOD) { draft["hour"] = (draft["hour"] + 12) % 24; }
        else if (state == INTERVAL) { draft["interval"] = wrap(draft["interval"] - direction, 1, 52); }
        else if (state == YEAR) { draft["year"] = wrap(draft["year"] - direction, 2020, 2099); clampDay(); }
        else if (state == MONTH) { draft["month"] = wrap(draft["month"] - direction, 1, 12); clampDay(); }
        else if (state == DAY) { draft["day"] = wrap(draft["day"] - direction, 1, AlarmData.daysInMonth(draft["year"], draft["month"])); }
    }

    private function clampDay() {
        var max = AlarmData.daysInMonth(draft["year"], draft["month"]);
        if (draft["day"] > max) { draft["day"] = max; }
    }

    function select() {
        notice = null;
        if (!store.readable) { store.load(); return; }
        if (state == LIST) { beginEdit(selection); }
        else if (state == ACTIONS) { selectAction(); }
        else if (state == TOOLS) { command = cursor == 0 ? 1 : 300; returnToList(null); }
        else if (state == HOUR) { go(MINUTE); }
        else if (state == MINUTE) { go(PERIOD); }
        else if (state == PERIOD) { go(PATTERN); }
        else if (state == PATTERN) { selectPattern(); }
        else if (state == DAYS) {
            if (cursor == 7) { go(INTERVAL); }
            else {
                var mask = draft["days"] ^ (1 << cursor);
                if (mask == 0) { notice = "Choose at least one day"; }
                else { draft["days"] = mask; }
            }
        } else if (state == INTERVAL) { go(REVIEW); }
        else if (state == YEAR) { go(MONTH); }
        else if (state == MONTH) { go(DAY); }
        else if (state == DAY) { go(REVIEW); }
        else if (state == REVIEW) {
            var id = draft["id"];
            if (draft["repeat"] == AlarmData.ONCE) {
                AlarmSchedule.setNextOneTime(draft, Time.now().value());
            }
            if (store.save(draft)) {
                selection = id == 0 ? store.records.size() - 1 : store.indexOf(id);
                returnToList("Saved to device");
            } else { notice = store.error; }
        } else if (state == DELETE) {
            if (cursor == 0) { state = ACTIONS; cursor = 2; }
            else if (store.remove(store.records[selection]["id"])) {
                if (selection >= store.records.size()) { selection = store.records.size(); }
                returnToList("Alarm deleted");
            } else { notice = store.error; }
        } else if (state == DISCARD) {
            if (cursor == 0) { state = _discardFrom; }
            else { returnToList(null); }
        }
    }

    private function selectAction() {
        if (cursor == 0) { beginEdit(selection); }
        else if (cursor == 1) {
            var item = store.records[selection];
            var enabled = !item["enabled"];
            if (store.setEnabled(item["id"], enabled)) { returnToList(enabled ? "Alarm enabled" : "Alarm disabled"); }
            else { notice = store.error; }
        } else if (cursor == 2) { state = DELETE; cursor = 0; }
        else if (cursor == 3) { beginEdit(store.records.size()); }
        else { command = cursor == 4 ? 1 : 300; returnToList(null); }
    }

    private function selectPattern() {
        if (cursor <= 2) {
            draft["repeat"] = AlarmData.WEEKLY;
            draft["days"] = [127, 31, 96][cursor];
            draft["interval"] = 1;
            // Keep the existing storage format; repeating alarms have no date editor.
            var today = AlarmData.create();
            draft["year"] = today["year"]; draft["month"] = today["month"]; draft["day"] = today["day"];
            go(REVIEW);
        } else if (cursor == 3) { draft["repeat"] = AlarmData.WEEKLY; go(DAYS); }
        else if (cursor == 4) { draft["repeat"] = AlarmData.INTERVAL; go(INTERVAL); }
        else {
            AlarmSchedule.setNextOneTime(draft, Time.now().value());
            go(REVIEW);
        }
    }

    function menu() {
        if (!store.readable) { return; }
        notice = null;
        if (state == LIST) {
            if (selection < store.records.size()) { state = ACTIONS; cursor = 0; }
            else { state = TOOLS; cursor = 0; }
        } else if (state == DAYS) { go(INTERVAL); }
    }

    // Returning false at the root lets the delegate exit the app normally.
    function back() {
        notice = null;
        if (state == LIST) { return false; }
        if (state == ACTIONS || state == TOOLS) { returnToList(null); }
        else if (state == DELETE) { state = ACTIONS; cursor = 2; }
        else if (state == DISCARD) { state = _discardFrom; }
        else if (_history.size() > 0) {
            state = _history[_history.size() - 1];
            _history = _history.slice(0, _history.size() - 1);
            cursor = state == PATTERN ? patternIndex() : 0;
        } else {
            _discardFrom = state;
            state = DISCARD;
            cursor = 0;
        }
        return true;
    }

    private function returnToList(message) {
        state = LIST;
        draft = {};
        _history = [];
        cursor = 0;
        notice = message;
    }
}
