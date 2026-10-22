pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Format') {
            steps {
                sh 'test -z "$(gofmt -l .)"'
            }
        }

        stage('Static analysis') {
            steps {
                sh 'go vet ./...'
            }
        }

        stage('Unit tests') {
            steps {
                sh 'go test ./...'
            }
        }

        stage('Build') {
            steps {
                sh 'mkdir -p dist && go build -trimpath -ldflags="-s -w" -o dist/diploma-service .'
                archiveArtifacts artifacts: 'dist/diploma-service', fingerprint: true
            }
        }
    }
}
