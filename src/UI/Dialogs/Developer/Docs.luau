--!strict
--[[
	Docs

	The developer portal's Docs: a quick start, the web bot payloads and
	starter servers to copy. docs/BOTS.md explains bots in full.
]]

local Browser = require(script.Parent.Parent.Parent.Parent.Core.Browser)
local Language = require(script.Parent.Parent.Parent.Parent.Core.Language)
local PanelKit = require(script.Parent.Parent.Kit.PanelKit)
local Shared = require(script.Parent.Shared)

local DOCS_URL = "https://github.com/Automata-Devs/team-chat-plugin/blob/main/docs/BOTS.md"

local NODE_STARTER = [==[// A Team Chat web bot (Node.js + Express)
// npm install express, then: TEAMCHAT_TOKEN=... node bot.js
const express = require("express");
const app = express();
app.use(express.json());
const TOKEN = process.env.TEAMCHAT_TOKEN; // from the portal

app.post("/teamchat", (req, res) => {
  if (req.get("X-TeamChat-Token") !== TOKEN) {
    return res.sendStatus(401);
  }
  const body = req.body;
  if (body.type === "ping") {
    return res.json({
      type: "pong",
      name: "Starter",
      description: "Says hello",
      commands: [{
        name: "hello",
        description: "Say hello",
        options: [{ name: "name", type: "string", required: false }],
      }],
    });
  }
  if (body.type === "command" && body.command === "hello") {
    const who = body.options.name || body.user.name;
    return res.json({
      type: "message",
      content: `Hello, **${who}**!`,
      components: [
        { label: "Wave back", style: "primary", customId: "wave" },
      ],
    });
  }
  if (body.type === "button" && body.customId === "wave") {
    const who = body.user.name;
    return res.json({ type: "update", content: `${who} waved` });
  }
  res.json({ type: "none" });
});

app.listen(3000);]==]

local PYTHON_STARTER = [==[# A Team Chat web bot (Python + Flask)
# pip install flask, then: TEAMCHAT_TOKEN=... python bot.py
import os
from flask import Flask, request, jsonify, abort

app = Flask(__name__)
TOKEN = os.environ["TEAMCHAT_TOKEN"]  # from the portal

HELLO = {
    "name": "hello",
    "description": "Say hello",
    "options": [
        {"name": "name", "type": "string", "required": False},
    ],
}
WAVE = {"label": "Wave back", "style": "primary", "customId": "wave"}

@app.post("/teamchat")
def teamchat():
    if request.headers.get("X-TeamChat-Token") != TOKEN:
        abort(401)
    body = request.get_json()
    if body["type"] == "ping":
        return jsonify(type="pong", name="Starter",
                       description="Says hello", commands=[HELLO])
    if body["type"] == "command" and body["command"] == "hello":
        who = body["options"].get("name") or body["user"]["name"]
        return jsonify(type="message",
                       content=f"Hello, **{who}**!",
                       components=[WAVE])
    if body["type"] == "button" and body["customId"] == "wave":
        who = body["user"]["name"]
        return jsonify(type="update", content=f"{who} waved")
    return jsonify(type="none")

app.run(port=3000)]==]

local REQUEST_EXAMPLE = [==[POST <your URL>
X-TeamChat-Token: <token>

{ "type": "command", "id": "8F1C…", "test": false,
  "bot": { "id": "…" },
  "user": { "id": 156, "name": "builderman" },
  "place": { "id": 1818 }, "conversation": "main",
  "command": "hello", "options": { "name": "Ana" },
  "args": ["Ana"] }

{ "type": "button", "customId": "wave",
  "message": { "id": "…", "content": "…" }, … }

{ "type": "ping" }
  -> answer { "type": "pong", "name", "commands": [ … ] }

{ "type": "followup", "id": "8F1C…" }
  (after a "deferred" answer, every 2 s)]==]

local ANSWER_EXAMPLE = [==[{ "type": "message", "content": "Hi **there**",
  "ephemeral": false,
  "embed": {
    "title": "Card", "description": "…", "color": "#5865F2",
    "fields": [ { "name": "A", "value": "1", "inline": true } ] },
  "components": [
    { "label": "Again", "style": "primary", "customId": "again" },
    { "label": "Docs", "style": "link", "url": "https://…" } ] }

{ "type": "update", … }   change the message the button is on
{ "type": "deferred" }    show "is thinking…", then answer followups
{ "type": "none" }        show nothing]==]

local STUDIO_EXAMPLE = [==[bot.commands.roll = {
	description = "Roll a die",
	options = {
		{ name = "sides", type = "integer", required = false },
	},
	run = function(ctx)
		local sides = ctx.options.sides or 6
		ctx.reply({
			content = "You rolled " .. math.random(sides),
			components = {
				{ label = "Roll again", customId = "again" },
			},
		})
	end,
}

function bot.onButton(ctx, customId)
	ctx.update("Rolled again: " .. math.random(6))
end]==]

local Docs = {}

function Docs.build(view: Shared.View, colors, nextOrder: () -> number)
	local card, z = view.card, view.z

	PanelKit.text(card, Language.t("dev.docs.quickStart"), "heading", nextOrder(), z, colors)
	PanelKit.text(card, Language.t("dev.docs.studioSteps"), "body", nextOrder(), z, colors)
	PanelKit.codeBox(card, STUDIO_EXAMPLE, nextOrder(), z, colors).Name = "StudioExample"
	PanelKit.text(card, Language.t("dev.docs.webSteps"), "body", nextOrder(), z, colors)
	PanelKit.text(card, Language.t("dev.docs.requests"), "heading", nextOrder(), z, colors)
	PanelKit.codeBox(card, REQUEST_EXAMPLE, nextOrder(), z, colors).Name = "Requests"
	PanelKit.text(card, Language.t("dev.docs.answers"), "heading", nextOrder(), z, colors)
	PanelKit.codeBox(card, ANSWER_EXAMPLE, nextOrder(), z, colors).Name = "Answers"
	PanelKit.text(card, Language.t("dev.docs.starters"), "heading", nextOrder(), z, colors)
	PanelKit.text(card, Language.t("dev.docs.copyHint"), "muted", nextOrder(), z, colors)
	PanelKit.text(card, "<b>Node.js</b>", "body", nextOrder(), z, colors)
	PanelKit.codeBox(card, NODE_STARTER, nextOrder(), z, colors).Name = "NodeStarter"
	PanelKit.text(card, "<b>Python</b>", "body", nextOrder(), z, colors)
	PanelKit.codeBox(card, PYTHON_STARTER, nextOrder(), z, colors).Name = "PythonStarter"
	PanelKit.text(card, Language.t("dev.docs.security"), "muted", nextOrder(), z, colors)
	PanelKit.button(card, Language.t("dev.docs.full"), "secondary", nextOrder(), z, colors, function()
		if not Browser.open(DOCS_URL) then
			view.setStatus(Language.t("links.copied", { url = DOCS_URL }))
		end
	end).Name =
		"FullDocs"
end

return Docs
