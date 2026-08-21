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
    database: 'postgres'
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
    tag: '63e9150'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//result?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
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
    tag: '63e9150'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//vote?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
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
    tag: '63e9150'
    build: {
      source: 'git::https://github.com/nellshamrell/example-voting-app.git//worker?ref=63e9150ca17af4ed05880d4245e486481f73fcb4'
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
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
  }
  dependsOn: [
    postgresDb
  ]
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
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
  }
  dependsOn: [
    redisCache
  ]
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
      }
    }
  }
  dependsOn: [
    postgresDb
    redisCache
  ]
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
