const functions = require("firebase-functions");
const {RtcTokenBuilder, RtcRole} = require("agora-access-token");

// Your Agora credentials
const APP_ID = "e699bb8476824950a5e0c382274bde54";
// Get this from Agora Console
const APP_CERTIFICATE = "03104b75504e407fb38d08f6dbb93864";

exports.generateAgoraToken = functions.https.onRequest((req, res) => {
  // Enable CORS
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    // Get parameters from POST request
    const {channelName, uid} = req.body;

    console.log("Received:", {channelName, uid});

    // Validate
    if (!channelName) {
      return res.status(400).json({error: "channelName is required"});
    }
    if (!uid) {
      return res.status(400).json({error: "uid is required"});
    }

    // Convert uid to number
    const uidInt = parseInt(uid);

    // Token expires in 24 hours
    const expirationTime = Math.floor(Date.now() / 1000) + (24 * 60 * 60);

    // Generate token
    const token = RtcTokenBuilder.buildTokenWithUid(
        APP_ID,
        APP_CERTIFICATE,
        channelName,
        uidInt,
        RtcRole.PUBLISHER,
        expirationTime,
    );

    console.log("Token generated for channel:", channelName);

    res.status(200).json({token});
  } catch (error) {
    console.error("Error:", error);
    res.status(500).json({error: "Server error"});
  }
});