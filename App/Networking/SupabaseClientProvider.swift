import Foundation
import Supabase

enum SupabaseConfig {
    static let projectURL = URL(string: "https://pjvgtmxyxrfhabyuefne.supabase.co")!
    static let publishableKey = "sb_publishable_giIYtZqephFHiRArzZQhuQ_zrjqk6hR"
    static let evidenceBucketName = "chore-evidence"
}

enum SupabaseClientProvider {
    static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.projectURL,
        supabaseKey: SupabaseConfig.publishableKey
    )
}

