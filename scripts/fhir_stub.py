"""
scripts/fhir_stub.py

Servidor FHIR de mentira, en Python puro (Flask), sin Docker.

Solo sirve para probar el LOADER y el EXTRACTOR sin depender de levantar el
contenedor real de HAPI FHIR (util si Docker Hub no responde en tu red).
Acepta cualquier bundle por POST /fhir (siempre devuelve 201, como si se
hubiera cargado bien) y responde a GET /fhir/<recurso> con un Bundle vacio,
para que el extractor pueda ejecutar su extraccion sin fallar.

NOTA: esto NO valida que tus bundles sean FHIR-validos ni que HAPI los
acepte de verdad — solo prueba la logica nueva de las colas SQS (que es lo
que hemos tocado). La carga real contra HAPI FHIR es el mismo codigo de
siempre, sin cambios.

Uso:
  pip install flask
  python scripts/fhir_stub.py
  (deja esta ventana abierta, escucha en http://localhost:8080/fhir)
"""
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/fhir", methods=["POST"])
def load_bundle():
    print("STUB FHIR: bundle recibido, respondiendo 201", flush=True)
    return jsonify({"resourceType": "Bundle", "type": "transaction-response"}), 201


@app.route("/fhir/<resource_type>", methods=["GET"])
def search(resource_type):
    print(f"STUB FHIR: búsqueda de {resource_type}, devolviendo vacío", flush=True)
    return jsonify({"resourceType": "Bundle", "entry": [], "link": []}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
