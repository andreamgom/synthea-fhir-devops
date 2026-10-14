"""
scripts/local_pipeline_test.py

Prueba local del pipeline asincrono SQS (datalake -> loader -> extractor)
usando LocalStack en vez de AWS real. No hace falta ninguna cuenta de AWS
ni credenciales de verdad.

Requisitos previos (una sola vez):
  pip install boto3

Antes de cada prueba, deben estar corriendo:
  1) LocalStack:
       docker run -d --name localstack -p 4566:4566 -e SERVICES=s3,sqs localstack/localstack
  2) El FHIR local del proyecto:
       docker compose -f deploy/local/docker-compose.yml up -d fhir-server

Uso:
  python scripts/local_pipeline_test.py setup
      Crea el bucket del datalake, los buckets de datamarts y las dos colas
      SQS con la misma notificacion S3->SQS que hay en terraform/modules/storage.
      Imprime las variables de entorno que hay que usar para loader.py y extractor.py.

  python scripts/local_pipeline_test.py upload <ruta_a_bundle.json>
      Sube un bundle FHIR de prueba a raw/fhir/ en el datalake simulado,
      disparando la notificacion S3 -> loader-trigger-queue.

  python scripts/local_pipeline_test.py status
      Muestra cuantos mensajes hay pendientes en cada cola ahora mismo.
"""
import sys
import os
import boto3

ENDPOINT = os.getenv("AWS_ENDPOINT_URL", "http://localhost:4566")
REGION = "us-east-1"
BUCKET = "test-fhir-datalake"
DM_BUCKETS = ["dm-paciente", "dm-funcional", "dm-episodio", "dm-procedimientos", "dm-diagnosticos"]


def clients():
    s3 = boto3.client("s3", endpoint_url=ENDPOINT, region_name=REGION)
    sqs = boto3.client("sqs", endpoint_url=ENDPOINT, region_name=REGION)
    return s3, sqs


def setup():
    s3, sqs = clients()

    s3.create_bucket(Bucket=BUCKET)
    for b in DM_BUCKETS:
        s3.create_bucket(Bucket=b)

    loader_url = sqs.create_queue(QueueName="loader-trigger-queue")["QueueUrl"]
    extractor_url = sqs.create_queue(QueueName="extractor-trigger-queue")["QueueUrl"]
    loader_arn = sqs.get_queue_attributes(
        QueueUrl=loader_url, AttributeNames=["QueueArn"]
    )["Attributes"]["QueueArn"]

    s3.put_bucket_notification_configuration(
        Bucket=BUCKET,
        NotificationConfiguration={
            "QueueConfigurations": [
                {
                    "QueueArn": loader_arn,
                    "Events": ["s3:ObjectCreated:*"],
                    "Filter": {
                        "Key": {
                            "FilterRules": [
                                {"Name": "prefix", "Value": "raw/fhir/"},
                                {"Name": "suffix", "Value": ".json"},
                            ]
                        }
                    },
                }
            ]
        },
    )

    print("Listo. Bucket, buckets de datamarts y colas creados en LocalStack.\n")
    print("Variables de entorno para el LOADER (ventana de terminal 3):")
    print(f'  $env:S3_BUCKET="{BUCKET}"')
    print(f'  $env:LOADER_TRIGGER_QUEUE_URL="{loader_url}"')
    print(f'  $env:EXTRACTOR_TRIGGER_QUEUE_URL="{extractor_url}"')
    print("\nVariables de entorno para el EXTRACTOR (ventana de terminal 4):")
    print(f'  $env:EXTRACTOR_TRIGGER_QUEUE_URL="{extractor_url}"')
    for b, var in zip(
        DM_BUCKETS,
        ["S3_DM_PACIENTE", "S3_DM_FUNCIONAL", "S3_DM_EPISODIO", "S3_DM_PROCEDIMIENTOS", "S3_DM_DIAGNOSTICOS"],
    ):
        print(f'  $env:{var}="{b}"')


def upload(path):
    s3, _ = clients()
    name = os.path.basename(path)
    s3.upload_file(path, BUCKET, f"raw/fhir/{name}")
    print(f"Subido: s3://{BUCKET}/raw/fhir/{name} — deberia disparar al loader en unos segundos")


def status():
    _, sqs = clients()
    for name in ["loader-trigger-queue", "extractor-trigger-queue"]:
        url = sqs.get_queue_url(QueueName=name)["QueueUrl"]
        attrs = sqs.get_queue_attributes(
            QueueUrl=url, AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"]
        )["Attributes"]
        print(name, attrs)


def datamarts():
    s3, _ = clients()
    for b in DM_BUCKETS:
        try:
            obj = s3.get_object(Bucket=b, Key=f"{b.replace('-', '_')}.json")
            print(f"--- {b} ---")
            print(obj["Body"].read().decode()[:500])
        except Exception as e:
            print(f"--- {b} --- (aun no hay datos: {e})")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "setup"
    if cmd == "setup":
        setup()
    elif cmd == "upload":
        upload(sys.argv[2])
    elif cmd == "status":
        status()
    elif cmd == "datamarts":
        datamarts()
    else:
        print("Comando desconocido. Usa: setup | upload <archivo> | status | datamarts")
