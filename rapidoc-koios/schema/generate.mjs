import yaml from "js-yaml"
import fs from "fs"

const extraDescription = `
  <div style="background: #efefef;padding: 20px 30px;margin-top: 30px;border-left: 5px solid #1940ED;">
    <div style="font-size:12px; font-weight:bold;margin-bottom:10px;">DESCRIPTION</div>
    <div>
      <p>XRAY/Graph Koios Tiny is a distributed API service for Cardano, built on the foundation of the open-source Koios API and inspired by the Koios team's exceptional work. It delivers the same reliable schema and data access in a lightweight, horizontally scalable architecture—designed for developers and platforms that need fast, efficient, and redundant access to Cardano blockchain data.</p>
    </div>
  </div>
  <div style="background: #efefef;padding: 20px 30px;margin-top: 30px;border-left: 5px solid #1940ED;">
    <div style="font-size:12px; font-weight:bold;margin-bottom:10px;">AUTHENTICATION & HIGHER USAGE LIMITS</div>
    <div>
      <p>For high-traffic applications, we recommend using the paid XRAY/Graph or original Koios API access (set Authorization header in Authentication section):</p>
      <ul>
        <li>XRAY/Graph: <a href="https://xray.app">https://xray.app</a></li>
        <li>Koios: <a href="https://koios.rest/">https://koios.rest/</a></li>
      </ul>
    </div>
  </div>
  <br /><br /><hr /><br /><br />
`

const servers = [
  {
    "url": "https://graph.xray.app/output/services/koios/mainnet/api/v1",
    "description": "Mainnet"
  },
  {
    "url": "https://graph.xray.app/output/services/koios/preprod/api/v1",
    "description": "Preprod"
  },
  {
    "url": "https://graph.xray.app/output/services/koios/preview/api/v1",
    "description": "Preview"
  },
]

try {
  // Fetch the YAML file from the URL
  const koiosYAML = "https://api.koios.rest/koiosapi.yaml"
  const outputPath = "./schema/openapi.json"
  const response = await fetch(koiosYAML)
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`)
  }
  const yamlText = await response.text()
  const parsedData = yaml.load(yamlText)

  // Add servers to the parsed data
  parsedData.servers = [...servers, ...parsedData.servers || []]

  // Add extra description to the info section
  parsedData.info.description = extraDescription + parsedData.info.description

  // Remove Security Schemes description
  parsedData.components.securitySchemes.bearerAuth = {
    ...parsedData.components.securitySchemes.bearerAuth,
    description: "",
  }

  // Remove ogmios methods from the JSON
  const ogmiosIndex = parsedData.tags.findIndex(tag => tag.name === "Ogmios")
  if (ogmiosIndex !== -1) {
    const omgiosObject = parsedData.tags[ogmiosIndex]
    parsedData.tags.splice(ogmiosIndex, 1)
    parsedData.tags = [...parsedData.tags, {
      "name": omgiosObject.name,
      "description": omgiosObject.description,
      "x-tag-expanded": false,
    }]
  }
  
  // Convert the modified data back to JSON
  const stringifiedData = JSON.stringify(parsedData, null, 2)

  // Replace custom styles 
  const replacedData = stringifiedData.replaceAll("background-color: #222;", "background-color: #f0f0f0b3;")

  // Write the modified JSON to the output file
  fs.writeFileSync(outputPath, replacedData)
} catch (error) {
  console.error("Error fetching or parsing YAML:", error)
}