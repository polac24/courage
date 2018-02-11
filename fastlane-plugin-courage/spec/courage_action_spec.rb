describe Fastlane::Actions::CourageAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The courage plugin is working!")

      Fastlane::Actions::CourageAction.run(nil)
    end
  end
end
