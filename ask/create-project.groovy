pipeline {
    input("projectName", "shadock") {
        description "Le nom du projet à créer"
    }
    input("language", "Java 21") {
        description "Le langage de programmation du projet"
    }
    input("framework", "Quarkus") {
        description "Le framework à utiliser pour le projet"
    }
    input("buildTool", "Maven") {
        description "L'outil de build à utiliser pour le projet"
    }
    input("groupId", "com.example") {
        description "L'identifiant de groupe pour le projet"
    }
    input("artifactId", "shadock") {
        description "L'identifiant de l'artéfact pour le projet"
    
    stage("Bootstrap du projet") {
        instruction("Creér un dépot Git pour le projet")
        
        tool("quarkus cli") {
            instruction("Créer un projet Quarkus avec les paramètres fournis")
        }

        tool("maven") {
            instruction("Compiler le projet avec Maven")
        }
        result {
            onSuccess {
                document("Documente le projet créé") {
                    args: file: "README.md" create: true
                }
                tool("git") {
                    instruction("Commit le bootstrap du projet")
                }
                output("Projet créé avec succès : ${projectName}")
            }
            onFailure {
                instruction("Dis moi pourquoi le bootstrap a échoué")
            }
        }
    }
}