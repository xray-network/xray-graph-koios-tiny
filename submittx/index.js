import express from 'express'
import Router from 'express-promise-router'
import { createInteractionContext, createTxSubmissionClient } from '@cardano-ogmios/client'

const PORT = 8700
const HOST = '0.0.0.0'

const app = express()
app.use(express.text())
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*')
  res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE')
  res.header('Access-Control-Allow-Headers', 'Content-Type')
  next()
})

const router = new Router()

router.post('/', async (req, res) => {
  const tx = req.body
  try {
    const context = await createInteractionContext(
      err => console.error(err),
      () => console.log("Connection closed."),
      { connection: { host: 'cardano-node-ogmios', port: 1337 } }
    )
    const client = await createTxSubmissionClient(context)
    const result = await client.submitTx(tx)
    res.send(result)
  }
  catch (error) {
    res.status(400).send(error)
  }
})

app.use('/submittx', router)

app.listen(PORT, HOST);
console.log(`Running on http://${HOST}:${PORT}`)
