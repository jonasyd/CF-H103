# ==============================================================================
# DISABLE VARIOUS OPTIMIZATIONS
# ==============================================================================
-dontshrink
-dontobfuscate
-dontoptimize

# ==============================================================================
# REGLAS DE EXCEPCIÓN PARA EL LECTOR RFID CHAFON
# ==============================================================================
# El modo Release (R8) cambia los nombres de las clases nativas para optimizar el APK.
# Esto rompe la comunicación de los callbacks y canales nativos hacia Flutter.
# Las siguientes líneas obligan al compilador a mantener intacto el SDK del fabricante.

# Mantiene intactas todas las clases, métodos y atributos dentro del paquete del archivo .aar de Chafon.
-keep class com.chafon.** { *; }

# Ignora las advertencias de referencias no resueltas dentro del SDK durante la compilación.
# Evita que el proceso de "build" se detenga por alertas internas del código del fabricante.
-dontwarn com.chafon.**
