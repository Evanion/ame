-- Owns AME_HistoryDB (declared in the TOC). The core addon loads this addon on demand and reads the table after
-- ADDON_LOADED; there is no logic here, so its SavedVariables are only parsed when history is actually needed.
AME_HistoryDB = AME_HistoryDB or {}
