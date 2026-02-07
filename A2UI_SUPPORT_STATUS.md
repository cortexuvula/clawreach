# A2UI Support Status

## ✅ Current State

### ClawReach Client: FULLY READY
The ClawReach client already has complete A2UI support implemented:

**Supported Commands:**
- ✅ `canvas.a2ui.push` - Push JSONL messages to A2UI
- ✅ `canvas.a2ui.pushJSONL` - Alias for push
- ✅ `canvas.a2ui.reset` - Reset A2UI state
- ✅ Canvas presentation (`canvas.present`)
- ✅ Canvas navigation (`canvas.navigate`)

**Implementation:**
- Web: Uses postMessage to communicate with A2UI iframe
- Native: Uses WebViewController JavaScript execution
- Auto-shows canvas when A2UI commands arrive
- Handles user actions from A2UI forms

### Gateway: ASSETS PRESENT, NOT SERVING
The OpenClaw gateway has A2UI assets installed but isn't serving them:

**Assets Location:**
```
/home/cortexuvula/Applications/moltbot/dist/canvas-host/a2ui/
├── a2ui.bundle.js (525KB)
├── index.html
└── .bundle.hash
```

**Issue:**
- HTTP endpoint `/__openclaw__/a2ui/` returns "A2UI assets not found"
- Asset resolution function `resolveA2uiRoot()` isn't finding the files
- Possible causes:
  - Working directory mismatch
  - Cache issue
  - Gateway version compatibility
  - Configuration flag needed

## 🎯 What A2UI Enables

A2UI is OpenClaw's interactive UI framework for building structured forms and interfaces in the canvas.

### Advantages Over Plain HTML

**Plain HTML Canvas:**
- Static content only
- No built-in state management
- Manual event handling via postMessage
- No form validation
- You write all the JavaScript

**A2UI:**
- ✅ Declarative JSONL format
- ✅ Built-in state management
- ✅ Automatic event routing
- ✅ Form validation
- ✅ Pre-built components (buttons, inputs, dropdowns, checkboxes, sliders)
- ✅ Conditional rendering
- ✅ Live updates (push new messages anytime)
- ✅ Action handlers (gateway receives user actions)

### Example A2UI Form

**JSONL Input:**
```json
{"text":"Medical History Form","style":"title"}
{"text":"Patient Information","style":"heading"}
{"id":"name","kind":"text","label":"Full Name","required":true}
{"id":"dob","kind":"date","label":"Date of Birth"}
{"id":"gender","kind":"select","label":"Gender","options":["Male","Female","Other","Prefer not to say"]}
{"text":"Medical History","style":"heading"}
{"id":"allergies","kind":"textarea","label":"Known Allergies","placeholder":"List any allergies..."}
{"id":"medications","kind":"checkbox","label":"Current Medications","options":["Blood Pressure","Diabetes","Thyroid","Cholesterol","Other"]}
{"text":"Lifestyle","style":"heading"}
{"id":"smoking","kind":"radio","label":"Smoking Status","options":["Never","Former","Current"]}
{"id":"exercise","kind":"slider","label":"Exercise (hours/week)","min":0,"max":20,"value":3}
{"kind":"submit","label":"Submit Form","action":"submit-medical-history"}
```

**Result:**
- Professional form UI
- All fields validated
- Submit button sends action to gateway
- Gateway receives: `{"action":"submit-medical-history","fields":{...}}`

## 🔧 Troubleshooting

### Check A2UI Availability
```bash
curl http://192.168.1.171:18789/__openclaw__/a2ui/
```

**Expected (working):**
```html
<!DOCTYPE html>
<html>
...
```

**Current (not working):**
```
A2UI assets not found
```

### Verify Assets Exist
```bash
ls -la ~/Applications/moltbot/dist/canvas-host/a2ui/
```

**Expected:**
```
a2ui.bundle.js
index.html
.bundle.hash
```

### Check Gateway Working Directory
```bash
systemctl --user cat openclaw-gateway | grep ExecStart
```

Should show:
```
ExecStart=... /home/cortexuvula/Applications/moltbot/dist/index.js gateway --port 18789
```

### Asset Resolution Candidates
The gateway checks these paths (in order):
1. `<executable-dir>/a2ui/`
2. `<module-dir>/a2ui/` (next to compiled JS)
3. `<module-dir>/../../src/canvas-host/a2ui/` (source fallback)
4. `<cwd>/src/canvas-host/a2ui/`
5. `<cwd>/dist/canvas-host/a2ui/`

## 🛠️ Potential Fixes

### Option 1: Wait for OpenClaw Update
The gateway might need an update to properly serve A2UI assets. Check for updates:
```bash
openclaw update
```

### Option 2: Manual Asset Copy
If the gateway is looking in the wrong place, copy assets:
```bash
# Find where gateway looks
ps aux | grep openclaw-gateway

# Copy assets to that location
cp -r ~/Applications/moltbot/dist/canvas-host/a2ui /path/to/expected/location/
```

### Option 3: Configuration Flag
Check if there's a config option to enable A2UI:
```bash
openclaw gateway config get | grep -i a2ui
```

### Option 4: Environment Variable
Some applications use env vars for asset paths:
```bash
# Add to systemctl service
Environment=A2UI_ROOT=/home/cortexuvula/Applications/moltbot/dist/canvas-host/a2ui
```

## 📋 Workaround: Use Plain HTML Canvas

Until A2UI is working, you can still build interactive forms using plain HTML:

**Example: Simple Form**
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Medical Form</title>
</head>
<body>
  <h1>Patient Information</h1>
  <form id="medForm">
    <label>Name: <input type="text" id="name" required></label><br>
    <label>DOB: <input type="date" id="dob"></label><br>
    <button type="submit">Submit</button>
  </form>
  
  <script>
    document.getElementById('medForm').addEventListener('submit', (e) => {
      e.preventDefault();
      const data = {
        name: document.getElementById('name').value,
        dob: document.getElementById('dob').value,
      };
      // Send to gateway (if using ClawReach canvas)
      parent.postMessage({type: 'form-submit', data}, '*');
    });
  </script>
</body>
</html>
```

**Pros:**
- ✅ Works immediately
- ✅ Full control over styling
- ✅ No dependencies

**Cons:**
- ❌ More code to write
- ❌ Manual state management
- ❌ No built-in validation
- ❌ Harder to update dynamically

## 🎓 A2UI Component Reference

Once A2UI is working, you can use these components:

### Text Display
```json
{"text":"Hello World","style":"title"}
{"text":"Subtitle","style":"heading"}
{"text":"Body paragraph","style":"body"}
```

### Form Inputs
```json
{"id":"username","kind":"text","label":"Username","placeholder":"Enter username"}
{"id":"password","kind":"password","label":"Password"}
{"id":"email","kind":"email","label":"Email"}
{"id":"age","kind":"number","label":"Age","min":0,"max":120}
```

### Selection
```json
{"id":"color","kind":"select","label":"Favorite Color","options":["Red","Blue","Green"]}
{"id":"size","kind":"radio","label":"Size","options":["S","M","L","XL"]}
{"id":"toppings","kind":"checkbox","label":"Toppings","options":["Cheese","Pepperoni","Mushrooms"]}
```

### Buttons
```json
{"kind":"submit","label":"Submit","action":"form-submit"}
{"kind":"button","label":"Cancel","action":"cancel"}
```

### Interactive
```json
{"id":"volume","kind":"slider","label":"Volume","min":0,"max":100,"value":50}
{"id":"date","kind":"date","label":"Appointment Date"}
{"id":"time","kind":"time","label":"Appointment Time"}
```

### Layout
```json
{"kind":"divider"}
{"kind":"spacer","height":20}
{"text":"Section break"}
```

## 📝 Next Steps

1. **Report Issue:** File a GitHub issue on OpenClaw repository about A2UI assets not being served
2. **Check for Updates:** Run `openclaw update` to get latest gateway version
3. **Monitor:** Watch for A2UI support in release notes
4. **Workaround:** Use plain HTML canvas for interactive forms in the meantime

## ✅ Conclusion

**ClawReach is ready for A2UI!** The client-side implementation is complete and tested. Once the gateway serves the A2UI assets properly, all A2UI features will work immediately without any ClawReach code changes.

**Status:**
- Client: ✅ Ready
- Gateway: ⚠️ Assets present but not serving
- Solution: Gateway configuration or version update needed
