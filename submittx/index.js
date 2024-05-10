import express from "express"

const HOST = "0.0.0.0"
const PORT = 8700
const OGMIOS_HOST = process.env.OGMIOS_HOST
const OGMIOS_PORT = process.env.OGMIOS_PORT

const app = express()
const router = express.Router()

app.use(express.text())
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*")
  res.header("Access-Control-Allow-Methods", "GET,PUT,POST,DELETE")
  res.header("Access-Control-Allow-Headers", "Content-Type")
  next()
})

router.post("/", async (req, res) => {
  const tx = req.body
  try {
    const response = await fetch(`http://${OGMIOS_HOST}:${OGMIOS_PORT}`, {
      method: 'POST',
      body: JSON.stringify({
        "jsonrpc": "2.0",
        "method": "submitTransaction",
        "params": {
          "transaction": {
            "cbor": tx,
          },
        },
      }),
    })

    const result = await response.json()
    res.status(response.status).send(result)
  }
  catch (error) {
    console.log("Submittx ::", new Date().toISOString(), "::", JSON.stringify(error))
    res.status(400).send(error)
  }
})

app.use('/submittx', router)

app.listen(PORT, HOST);
console.log(`Running on http://${HOST}:${PORT}`)
