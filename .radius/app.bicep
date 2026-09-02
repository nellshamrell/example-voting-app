extension radius

param environment string

@secure()
param postgresPassword string

@secure()
param registryPassword string

@secure()
param registryUsername string

resource exampleVotingApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'example-voting-app'
  properties: {
    environment: environment
  }
}

resource postgresDb 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'postgres'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'worker/Program.cs#L69'
    database: 'votes'
    password: postgresPassword
    username: 'myadmin'
  }
}

resource redisCache 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'vote/app.py#L20'
  }
}

resource postgresClientSecret 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'postgres-client-credentials'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'worker/Program.cs#L69'
    data: {
      password: {
        value: postgresPassword
      }
    }
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: '.radius/app.bicep'
    data: {
      password: {
        value: registryPassword
      }
      username: {
        value: registryUsername
      }
    }
  }
}

resource resultImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'result-image'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'result/Dockerfile#L1'
    build: {
      platforms: [
        'linux/amd64'
      ]
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//result?ref=16a6fe1d34edc26b59f7ba966e4277d4695e932b'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource voteImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'vote-image'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'vote/Dockerfile#L1'
    build: {
      platforms: [
        'linux/amd64'
      ]
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//vote?ref=16a6fe1d34edc26b59f7ba966e4277d4695e932b'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource workerImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'worker-image'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'worker/Dockerfile#L1'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//worker?ref=16a6fe1d34edc26b59f7ba966e4277d4695e932b'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource resultContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'result'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'result/server.js#L79'
    containers: {
      result: {
        image: resultImage.properties.imageReference
        env: {
          POSTGRES_DATABASE: {
            value: 'votes'
          }
          POSTGRES_HOST: {
            value: postgresDb.properties.host
          }
          POSTGRES_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                secretName: postgresClientSecret.name
                key: 'password'
              }
            }
          }
          POSTGRES_PORT: {
            value: '5432'
          }
          POSTGRES_SSL: {
            value: 'true'
          }
          POSTGRES_USER: {
            value: 'myadmin'
          }
        }
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    replicas: 1
  }
}

resource voteContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'vote'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'vote/app.py#L14'
    containers: {
      vote: {
        image: voteImage.properties.imageReference
        env: {
          REDIS_URL: {
            valueFrom: {
              secretKeyRef: {
                secretName: redisCache.properties.secrets.name
                key: 'url'
              }
            }
          }
        }
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    replicas: 1
  }
}

resource workerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'worker'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'worker/Program.cs#L15'
    containers: {
      worker: {
        image: workerImage.properties.imageReference
        env: {
          POSTGRES_DATABASE: {
            value: 'votes'
          }
          POSTGRES_HOST: {
            value: postgresDb.properties.host
          }
          POSTGRES_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                secretName: postgresClientSecret.name
                key: 'password'
              }
            }
          }
          POSTGRES_PORT: {
            value: '5432'
          }
          POSTGRES_SSL: {
            value: 'true'
          }
          POSTGRES_USER: {
            value: 'myadmin'
          }
          REDIS_URL: {
            valueFrom: {
              secretKeyRef: {
                secretName: redisCache.properties.secrets.name
                key: 'url'
              }
            }
          }
        }
      }
    }
    replicas: 1
  }
}

resource resultRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'result-route'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'k8s-specifications/result-service.yaml#L8'
    kind: 'HTTP'
    rules: [
      {
        matches: [
          {
            httpPath: '/'
          }
        ]
        destinationContainer: {
          resourceId: resultContainer.id
          containerName: 'result'
          containerPort: 80
        }
      }
    ]
  }
}

resource voteRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'vote-route'
  properties: {
    environment: environment
    application: exampleVotingApp.id
    codeReference: 'k8s-specifications/vote-service.yaml#L8'
    kind: 'HTTP'
    rules: [
      {
        matches: [
          {
            httpPath: '/'
          }
        ]
        destinationContainer: {
          resourceId: voteContainer.id
          containerName: 'vote'
          containerPort: 80
        }
      }
    ]
  }
}
