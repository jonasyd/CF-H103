pipeline {
    agent { label 'linux' }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build APK') {
            steps {
                // Usamos ${WORKSPACE} que es la variable de Jenkins para el root
                // Se recomienda usar comillas simples para que Jenkins no intente expandir variables antes que Docker
                sh '''
					# Ejecutamos TODO dentro de Docker para que root se encargue de la limpieza
                    docker run --rm -v "${WORKSPACE}":/app \
                      -v /mnt/data/docker-volumes/pub-cache-clean:/root/.pub-cache \
					  -v /mnt/data/docker-volumes/gradle-cache:/root/.gradle \
                      -w /app \
                      flutter-android35-ready:latest \
					  bash -c "
						# 1. Borrar con permisos de root antes de empezar
						rm -rf build/
						
						# 2. Compilar
						flutter doctor && \
						flutter pub get && \
						flutter build apk --verbose && \
						flutter build apk --profile --verbose && \
						flutter build apk --debug --verbose
					  "
				'''
			}
		}
    }

    post {

        success {
            archiveArtifacts artifacts: 'build/app/outputs/flutter-apk/*.apk'
        }

        always {
            script {
				def result = currentBuild.currentResult ?: "UNKNOWN"

				if (result == "SUCCESS") {
					def logLine = "${new Date().format('yyyy-MM-dd HH:mm:ss')} - Job: ${env.JOB_NAME}, " +
								  "Build: ${env.BUILD_NUMBER}, " +
								  "Branch: ${env.BRANCH_NAME ?: 'N/A'}, " +
								  "Commit: ${env.GIT_COMMIT ?: 'N/S'}, " +
								  "Result: ${currentBuild.currentResult ?: 'UNKNOWN'}\n"

					// Write on CONTROLLER using Groovy/Jenkins JVM
					// CONTROLLER path (Windows Jenkins Home)
					def logFile = new File(env.JENKINS_HOME, "builds_log.txt")

					logFile.append(logLine)
				}

                // Discord notification (success / failure / aborted)
				withCredentials([string(credentialsId: 'discord-webhook', variable: 'WEBHOOK_URL')]) {

					def branch = env.BRANCH_NAME ?: "N/A"
					def commit = env.GIT_COMMIT ?: "N/S"

					def emoji = "📢"

					if (result == "SUCCESS") {
						emoji = "[OK]"
					} else if (result == "FAILURE") {
						emoji = "[FAIL]"
					} else if (result == "ABORTED") {
						emoji = "[STOP]"
					}

					def message =
						"${emoji} Job: ${env.JOB_NAME} #${env.BUILD_NUMBER}\n" +
						"Branch: ${branch}\n" +
						"Commit: ${commit}\n" +
						"Result: ${result}\n" +
						"${env.BUILD_URL}"

					def safeMessage = message
						.replace("\\", "\\\\")
						.replace("\"", "\\\"")
						.replace("\n", "\\n")

					def jsonPayload = "{\"content\":\"${safeMessage}\"}"

					withEnv(["JSON_PAYLOAD=${jsonPayload}"]) {
						sh '''
							curl -sS \
							  -H "Content-Type: application/json" \
							  -X POST \
							  -d "$JSON_PAYLOAD" \
							  "$WEBHOOK_URL"
						'''
					}
				}
            }
        }
    }
}
