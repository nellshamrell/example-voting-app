extension radius

param environment string

@secure()
param postgresPassword string

@secure()
param registryPassword string

@secure()
param registryUsername string

resource exampleVotingAppApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'example-voting-app'
  properties: {
    environment: environment
  }
}

resource postgresDb 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'db'
  properties: {
    environment: environment
    application: exampleVotingAppApp.id
    codeReference: 'docker-compose.yml#L64'
    database: 'voting'
    password: postgresPassword
    username: 'postgres'
  }
}

resource redisCache 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    environment: environment
    application: exampleVotingAppApp.id
    codeReference: 'docker-compose.yml#L54'
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: exampleVotingAppApp.id
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
    application: exampleVotingAppApp.id
    codeReference: 'result/Dockerfile#L1'
    tag: '1963aa3'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//result?ref=1963aa3305def5f99e7bf0cd31d06f2be1e5e829'
      platforms: [
        'linux/amd64'
      ]
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
    application: exampleVotingAppApp.id
    codeReference: 'vote/Dockerfile#L1'
    tag: '1963aa3'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//vote?ref=1963aa3305def5f99e7bf0cd31d06f2be1e5e829'
      platforms: [
        'linux/amd64'
      ]
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
    application: exampleVotingAppApp.id
    codeReference: 'worker/Dockerfile#L11'
    tag: '1963aa3'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//worker?ref=1963aa3305def5f99e7bf0cd31d06f2be1e5e829'
      platforms: [
        'linux/amd64'
      ]
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
    application: exampleVotingAppApp.id
    codeReference: 'result/Dockerfile#L24'
    containers: {
      result: {
        image: resultImage.properties.imageReference
        env: {
          POSTGRES_HOST: {
            value: postgresDb.properties.host
          }
          POSTGRES_PORT: {
            value: '5432'
          }
          POSTGRES_USER: {
            value: 'postgres'
          }
          POSTGRES_PASSWORD: {
            value: postgresPassword
          }
          POSTGRES_DB: {
            value: 'voting'
          }
          POSTGRES_SSLMODE: {
            value: 'require'
          }
        }
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
  }
}

resource voteContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'vote'
  properties: {
    environment: environment
    application: exampleVotingAppApp.id
    codeReference: 'vote/Dockerfile#L23'
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
  }
}

resource workerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'worker'
  properties: {
    environment: environment
    application: exampleVotingAppApp.id
    codeReference: 'worker/Dockerfile#L25'
    containers: {
      worker: {
        image: workerImage.properties.imageReference
        env: {
          POSTGRES_HOST: {
            value: postgresDb.properties.host
          }
          POSTGRES_PORT: {
            value: '5432'
          }
          POSTGRES_USER: {
            value: 'postgres'
          }
          POSTGRES_PASSWORD: {
            value: postgresPassword
          }
          POSTGRES_DB: {
            value: 'voting'
          }
          POSTGRES_SSLMODE: {
            value: 'require'
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
  }
}

resource resultRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'result-route'
  properties: {
    environment: environment
    application: exampleVotingAppApp.id
    codeReference: 'docker-compose.yml#L27'
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
    application: exampleVotingAppApp.id
    codeReference: 'docker-compose.yml#L6'
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
