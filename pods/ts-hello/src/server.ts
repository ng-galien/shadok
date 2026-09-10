import { createServer } from "node:http";
createServer((_request, response) => { response.end("ts-baseline"); }).listen(8080, "0.0.0.0");
