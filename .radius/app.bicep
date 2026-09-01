extension radius

param environment string

@description('Username for the OCI registry used by Radius image builds.')
@secure()
param registryUsername string

@description('Token with permission to push Radius image builds to the OCI registry.')
@secure()
param registryPassword string

@description('Administrator password for PostgreSQL.')
@secure()
param postgresPassword string

resource votingApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'example-voting-app'
  properties: {
    environment: environment
  }
}

resource postgresDb 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'postgres'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'result/server.js#L20'
    size: 'S'
    database: 'postgres'
    username: 'postgres'
    password: postgresPassword
  }
}

resource redisCache 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'vote/app.py#L19'
    size: 'S'
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: '.github/workflows/run-rad-commands-azure.yml#L219'
    data: {
      username: {
        value: registryUsername
      }
      password: {
        value: registryPassword
      }
    }
  }
}

resource voteImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'vote-image'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'vote/Dockerfile#L1'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//vote?ref=7fe2b96a3aa64db500182eb59bbe722248f67d16'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource resultImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'result-image'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'result/Dockerfile#L1'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//result?ref=7fe2b96a3aa64db500182eb59bbe722248f67d16'
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
    application: votingApp.id
    codeReference: 'worker/Dockerfile#L11'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//worker?ref=7fe2b96a3aa64db500182eb59bbe722248f67d16'
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource voteContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'vote'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'vote/app.py#L50'
    containers: {
      vote: {
        image: voteImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    connections: {
      rediscache: {
        source: redisCache.id
      }
    }
  }
}

resource resultContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'result'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'result/server.js#L74'
    containers: {
      result: {
        image: resultImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
    connections: {
      postgresdb: {
        source: postgresDb.id
      }
    }
  }
}

resource workerContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'worker'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'worker/Program.cs#L15'
    containers: {
      worker: {
        image: workerImage.properties.imageReference
      }
    }
    connections: {
      postgresdb: {
        source: postgresDb.id
      }
      rediscache: {
        source: redisCache.id
      }
    }
  }
}

resource voteRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'vote-route'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'docker-stack.yml#L24'
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

resource resultRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'result-route'
  properties: {
    environment: environment
    application: votingApp.id
    codeReference: 'docker-stack.yml#L33'
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
