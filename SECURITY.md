# Política de seguridad

Si encuentras una vulnerabilidad, **no abras un issue público**. Usa la
funcionalidad *Report a vulnerability* de GitHub (Security → Advisories) del
repositorio, indicando versión, pasos de reproducción e impacto.

Principios de diseño relevantes: mínimo privilegio en IAM, el state crudo nunca
se guarda en DynamoDB, los atributos sensibles se enmascaran en la ingesta y
la API exige un JWT de Amazon Cognito.
