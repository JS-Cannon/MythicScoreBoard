_G["MythicScoreboard"] = _G["MythicScoreboard"] or {}
local MS = _G["MythicScoreboard"]

-- TOC is authoritative at runtime; fallback for dev environments.
MS.version = GetAddOnMetadata and GetAddOnMetadata("MythicScoreboard", "Version") or "1.2"
