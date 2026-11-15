package kg.adamrun.adam_run

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

class PrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply {
            text = "ADAM RUN — данные активности\n\nПриложение читает только количество шагов, чтобы показать дневную цель и последние 7 дней. Health Connect объединяет источники; приложение не складывает их повторно.\n\nШаги и GPS этой тестовой версии хранятся на устройстве. Сервер хранит email, никнейм и дневную цель.\n\nДоступ можно отозвать в настройках Health Connect. Приложение не записывает шаги в Health Connect."
            textSize = 18f
            setPadding(32, 64, 32, 32)
        })
    }
}
