#!/usr/bin/env python3
"""SleepMate 동기화 단축어(.shortcut, 서명 전 plist)를 생성한다. 1차: 서명 시험용 최소 단축어."""
import os
import plistlib
import sys
import uuid

out = sys.argv[1]
os.makedirs(os.path.dirname(out), exist_ok=True)

url_uuid = str(uuid.uuid4()).upper()
actions = [
    {
        "WFWorkflowActionIdentifier": "is.workflow.actions.url",
        "WFWorkflowActionParameters": {"UUID": url_uuid, "WFURLActionURL": "sleepmate://import"},
    },
    {
        "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
        "WFWorkflowActionParameters": {},
    },
]

wf = {
    "WFWorkflowActions": actions,
    "WFWorkflowClientVersion": "2607.0.2",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59511},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowOutputContentItemClasses": [],
    "WFWorkflowTypes": [],
    "WFQuickActionSurfaces": [],
    "WFWorkflowHasShortcutInputVariables": False,
}

with open(out, "wb") as f:
    plistlib.dump(wf, f, fmt=plistlib.FMT_BINARY)
print("wrote", out)
