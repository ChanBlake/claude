/* Entry point. Kept deliberately thin so the engine can be driven by
   something other than a browser page — tests, the editor, a native shell. */
import {boot} from "./game.js";
import {loadSave} from "./save.js";

loadSave().finally(boot);
